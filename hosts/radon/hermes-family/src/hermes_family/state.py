"""Files under ${hermesHome}/state that the scripts share, and the run log."""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from email.utils import parseaddr
from pathlib import Path

KEY_RE = re.compile(r"[0-9a-f]{32}")
FETCH_RECORD_KEEP = 500

PROCESSED_LABEL = "hermes-processed"
IGNORED_LABEL = "hermes-ignored"


def mail_key(message_id: str) -> str:
    """First 32 hex characters of SHA-256 of the raw Message-ID. The ledger,
    the parse result and each Proposals event id derive from it."""
    return hashlib.sha256(message_id.strip().encode()).hexdigest()[:32]


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


class State:
    def __init__(self, directory: Path):
        self.dir = Path(directory)
        self.senders_file = self.dir / "senders.txt"
        self.ledger_file = self.dir / "mail-ledger.txt"
        self.fetch_record_file = self.dir / "fetch-record.jsonl"
        self.notifier_cursor_file = self.dir / "notifier-cursor"

    def senders(self) -> frozenset[str]:
        """Allowlisted sender addresses. A missing file allows nobody."""
        try:
            lines = self.senders_file.read_text().splitlines()
        except FileNotFoundError:
            return frozenset()
        return frozenset(
            line.strip().lower() for line in lines if line.strip() and not line.lstrip().startswith("#")
        )

    def ledger(self) -> set[str]:
        try:
            return {line.strip() for line in self.ledger_file.read_text().splitlines() if line.strip()}
        except FileNotFoundError:
            return set()

    def append_ledger(self, keys: list[str]) -> None:
        if keys:
            with self.ledger_file.open("a") as handle:
                handle.write("".join(f"{key}\n" for key in keys))

    def record_fetch(self, mails: dict[str, str], now: datetime) -> None:
        """Append the keys this mail-fetch run printed, with their Gmail ids."""
        line = json.dumps({"ts": now.isoformat(), "mails": mails}, sort_keys=True)
        try:
            kept = self.fetch_record_file.read_text().splitlines()[-(FETCH_RECORD_KEEP - 1):]
        except FileNotFoundError:
            kept = []
        write_atomic(self.fetch_record_file, "".join(f"{row}\n" for row in [*kept, line]))

    def fetched(self) -> dict[str, str]:
        """Key -> Gmail id for every key mail-fetch printed in the kept runs."""
        mails: dict[str, str] = {}
        try:
            lines = self.fetch_record_file.read_text().splitlines()
        except FileNotFoundError:
            return mails
        for line in lines:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            for key, gmail_id in (row.get("mails") or {}).items():
                if is_key(key) and isinstance(gmail_id, str):
                    mails[key] = gmail_id
        return mails

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
