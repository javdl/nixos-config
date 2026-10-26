"""Files under ${hermesHome}/state that the scripts share, and the run log."""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parseaddr
from pathlib import Path

KEY_RE = re.compile(r"[0-9a-f]{32}")
ADDRESS_RE = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
RECORD_KEEP = 500

PROCESSED_LABEL = "hermes-processed"
IGNORED_LABEL = "hermes-ignored"
QUARANTINED_LABEL = "hermes-quarantined"


def mail_key(message_id: str) -> str:
    """First 32 hex characters of SHA-256 of the raw Message-ID. The ledger,
    the parse result and each Proposals event id derive from it."""
    return hashlib.sha256(message_id.strip().encode()).hexdigest()[:32]


def gmail_key(gmail_id: str) -> str:
    """The key of a mail without a Message-ID: the same hash of a newline,
    "gmail-id:" and Gmail's message id. A trimmed Message-ID never starts
    with a newline, so this never equals a mail_key input."""
    return hashlib.sha256(f"\ngmail-id:{gmail_id}".encode()).hexdigest()[:32]


def is_key(value: object) -> bool:
    return isinstance(value, str) and KEY_RE.fullmatch(value) is not None


def address(sender: str) -> str:
    """The lower-cased address of a From value, or "" when it has none."""
    found = parseaddr(sender)[1].strip().lower()
    return found if "@" in found else ""


def write_atomic(path: Path, text: str) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(text)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def _rows(path: Path) -> list[dict]:
    try:
        lines = path.read_text().splitlines()
    except FileNotFoundError:
        return []
    rows = []
    for line in lines:
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def _append_kept(path: Path, row: dict) -> None:
    """Append one JSON row, keeping the last RECORD_KEEP rows."""
    try:
        kept = path.read_text().splitlines()[-(RECORD_KEEP - 1):]
    except FileNotFoundError:
        kept = []
    write_atomic(path, "".join(f"{line}\n" for line in [*kept, json.dumps(row, sort_keys=True)]))


def _time(value: object) -> datetime | None:
    try:
        moment = datetime.fromisoformat(value) if isinstance(value, str) else None
    except ValueError:
        return None
    return moment if moment and moment.tzinfo else None


@dataclass(frozen=True)
class Head:
    sender: str
    subject: str
    date: str


@dataclass(frozen=True)
class MailKey:
    """What mail-fetch last printed under a mail key: the Gmail message id and
    the Message-ID ("" for a mail keyed by its Gmail id), when, and the
    headers when it cut the body."""

    gmail_id: str
    message_id: str
    at: datetime
    truncated: Head | None = None


@dataclass(frozen=True)
class Quarantined:
    key: str
    sender: str
    subject: str
    date: str


class State:
    def __init__(self, directory: Path):
        self.dir = Path(directory)
        self.senders_file = self.dir / "senders.txt"
        self.ledger_file = self.dir / "mail-ledger.txt"
        self.mail_keys_file = self.dir / "mail-keys.txt"
        self.notifier_cursor_file = self.dir / "notifier-cursor"
        self.quarantine_file = self.dir / "quarantine.txt"
        self.quarantine_cursor_file = self.dir / "quarantine-cursor"
        self.proposal_failures_file = self.dir / "proposal-failures.jsonl"

    def senders(self) -> frozenset[str]:
        """Allowlisted sender addresses: the lines that are an address. A
        missing file, or one without a valid address, allows nobody."""
        try:
            lines = self.senders_file.read_text().splitlines()
        except FileNotFoundError:
            return frozenset()
        return frozenset(line.strip().lower() for line in lines if ADDRESS_RE.fullmatch(line.strip()))

    def ledger(self) -> set[str]:
        try:
            return {line.strip() for line in self.ledger_file.read_text().splitlines() if line.strip()}
        except FileNotFoundError:
            return set()

    def append_ledger(self, keys: list[str]) -> None:
        if keys:
            with self.ledger_file.open("a") as handle:
                handle.write("".join(f"{key}\n" for key in keys))

    def record_mail_keys(self, mails: dict[str, MailKey]) -> None:
        """mail-keys.txt, one JSON line per key: the keys this mail-fetch run
        printed replace their old lines, and the last RECORD_KEEP keys stay.
        The file is replaced whole, so a reader sees the old map or the new
        one, never part of either."""
        rows = [row for row in _rows(self.mail_keys_file) if row.get("key") not in mails]
        for key, mail in mails.items():
            row = {"key": key, "gmail_id": mail.gmail_id, "message_id": mail.message_id, "ts": mail.at.isoformat()}
            if mail.truncated:
                row["truncated"] = {"from": mail.truncated.sender, "subject": mail.truncated.subject,
                                    "date": mail.truncated.date}
            rows.append(row)
        write_atomic(self.mail_keys_file, "".join(f"{json.dumps(row, sort_keys=True)}\n" for row in rows[-RECORD_KEEP:]))

    def mail_keys(self) -> dict[str, MailKey]:
        """Every key in mail-keys.txt: the keys mail-fetch showed a model."""
        mails: dict[str, MailKey] = {}
        for row in _rows(self.mail_keys_file):
            key, at = row.get("key"), _time(row.get("ts"))
            gmail_id, message_id = row.get("gmail_id"), row.get("message_id")
            if not (is_key(key) and isinstance(gmail_id, str) and isinstance(message_id, str) and at is not None):
                continue
            head = row.get("truncated")
            truncated = Head(*(str(head.get(f, "")) for f in ("from", "subject", "date"))) if isinstance(head, dict) else None
            mails[key] = MailKey(gmail_id, message_id, at, truncated)
        return mails

    def record_proposal_failure(self, key: str, now: datetime) -> None:
        """gcal-mcp: Google refused or did not answer a proposal for this mail."""
        _append_kept(self.proposal_failures_file, {"ts": now.isoformat(), "key": key})

    def proposal_failures(self) -> dict[str, datetime]:
        """Key -> time of its last failed proposal."""
        failures: dict[str, datetime] = {}
        for row in _rows(self.proposal_failures_file):
            at, key = _time(row.get("ts")), row.get("key")
            if at is not None and is_key(key):
                failures[key] = max(at, failures.get(key, at))
        return failures

    def quarantine(self, entry: Quarantined) -> None:
        line = json.dumps({"key": entry.key, "from": entry.sender, "subject": entry.subject, "date": entry.date})
        with self.quarantine_file.open("a") as handle:
            handle.write(f"{line}\n")

    def quarantined(self) -> list[Quarantined]:
        """Every line mail-fetch wrote, in order. A line that does not parse
        keeps its place, as an entry the notifier rejects."""
        try:
            lines = self.quarantine_file.read_text().splitlines()
        except FileNotFoundError:
            return []
        entries = []
        for line in lines:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                row = None
            if not isinstance(row, dict):
                row = {}
            entries.append(Quarantined(*(str(row.get(field, "")) for field in ("key", "from", "subject", "date"))))
        return entries

    def quarantine_cursor(self) -> int:
        """How many quarantine lines the notifier has handled."""
        try:
            return int(self.quarantine_cursor_file.read_text().strip() or 0)
        except (FileNotFoundError, ValueError):
            return 0

    def set_quarantine_cursor(self, count: int) -> None:
        write_atomic(self.quarantine_cursor_file, f"{count}\n")

    def notifier_cursor(self) -> str:
        try:
            return self.notifier_cursor_file.read_text().strip()
        except FileNotFoundError:
            return ""

    def set_notifier_cursor(self, name: str) -> None:
        write_atomic(self.notifier_cursor_file, f"{name}\n")


def log_failure(run_log: Path | None, job: str, error: str) -> None:
    """One run-log row in the shape the gateway's run collector writes."""
    if run_log is None:
        return
    row = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "job": job,
        "model": None,
        "provider": None,
        "input_tokens": None,
        "output_tokens": None,
        "cost": None,
        "duration_s": None,
        "status": "failed",
        "model_host_failure": False,
        "error": " ".join(error.split())[:500],
    }
    with Path(run_log).open("a") as handle:
        handle.write(json.dumps(row) + "\n")
