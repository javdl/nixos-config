"""notifier: the only path from the mail-parsing job to the family group.

A no-agent cron job, so Hermes delivers its stdout to the job's --deliver
target and an empty stdout sends nothing. It reads the parsing job's run
documents newer than its cursor, takes the last fenced JSON block of each
model answer, ledgers and labels the processed keys that mail-fetch printed,
and prints the fixed template for each uncertain mail, and for each mail
whose body mail-fetch cut, from the headers mail-fetch recorded. A key whose
proposal failed at Google after mail-fetch last printed it stays out of the
ledger, so the next parsing run tries that mail again; so does a key whose
notice has no allowlisted sender or no date, with a failure row. It also
prints the fixed template for each mail that mail-fetch quarantined since the
last run, without the date when its Date header does not parse.
Model text never reaches the output: every printed field is re-derived or
sanitized.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from dataclasses import dataclass
from datetime import date, datetime
from email.utils import parsedate_to_datetime
from pathlib import Path

from hermes_family.google import Api, Gmail, GoogleError
from hermes_family.state import PROCESSED_LABEL, State, address, log_failure

JOB_NAME = "family-mail-notifier"
PARSE_JOB_NAME = "family-mail-parsing"
TEMPLATE = "Kon geen datum vinden: {sender}, {subject} ({received}). Kijk de mail even na."
QUARANTINE_TEMPLATE = "Kon de mail niet lezen: {sender}, {subject} ({received}). Kijk de mail even na."
UNDATED_QUARANTINE_TEMPLATE = "Kon de mail niet lezen: {sender}, {subject}. Kijk de mail even na."
SUBJECT_LIMIT = 80

# Hermes 81a5543 writes an agent run as header, "**Prompt Characters:** N",
# "## Prompt", the prompt, a blank line, "**Response Characters:** M",
# "## Response", the answer and "\n" (cron/scheduler.py:2638-2647, frames in
# cron/scheduler_prompt.py:70-79). The prompt holds the untrusted mail, so the
# answer is located by the frame lengths, never by searching the text.
PROMPT_FRAME_RE = re.compile(r"(?m)^\*\*Prompt Characters:\*\* (\d+)\n## Prompt\n\n")
RESPONSE_FRAME_RE = re.compile(r"\*\*Response Characters:\*\* (\d+)\n## Response\n\n")
FENCE_RE = re.compile(r"```[ \t]*(?:json)?[ \t]*\n(.*?)\n[ \t]*```", re.DOTALL | re.IGNORECASE)
URL_RE = re.compile(r"(?:[a-z][a-z0-9+.-]*://|www\.)\S+", re.IGNORECASE)


class NoAnswer(Exception):
    """A run document without a model answer: a skipped (no mail) or failed run."""


class InvalidBlock(ValueError):
    pass


@dataclass(frozen=True)
class Uncertain:
    key: str
    sender: str
    subject: str
    received: str


@dataclass(frozen=True)
class ParseResult:
    processed: tuple[str, ...]
    uncertain: tuple[Uncertain, ...]


def answer(document: str) -> str:
    prompt = PROMPT_FRAME_RE.search(document)
    if prompt is None:
        raise NoAnswer
    response_start = prompt.end() + int(prompt.group(1)) + len("\n\n")
    frame = RESPONSE_FRAME_RE.match(document, response_start)
    if frame is None:
        raise NoAnswer
    text = document[frame.end() :]
    length = int(frame.group(1))
    if len(text) != length + 1 or not text.endswith("\n"):
        raise InvalidBlock("run document is truncated")
    return text[:length]


def parse_block(text: str) -> ParseResult:
    blocks = FENCE_RE.findall(text)
    if not blocks:
        raise InvalidBlock("answer has no fenced JSON block")
    try:
        data = json.loads(blocks[-1])
    except json.JSONDecodeError as error:
        raise InvalidBlock(f"last fenced block is not JSON: {error}") from error
    if not isinstance(data, dict):
        raise InvalidBlock("last fenced block is not an object")
    processed = data.get("processed")
    uncertain = data.get("uncertain", [])
    if not isinstance(processed, list) or not isinstance(uncertain, list):
        raise InvalidBlock("processed and uncertain must be lists")
    entries = []
    for item in uncertain:
        if not isinstance(item, dict):
            raise InvalidBlock("uncertain entries must be objects")
        entries.append(
            Uncertain(*(str(item.get(field, "")) for field in ("key", "from", "subject", "received")))
        )
    return ParseResult(tuple(str(key) for key in processed), tuple(entries))


def clean_subject(subject: str) -> str:
    visible = "".join(" " if unicodedata.category(ch).startswith("C") else ch for ch in subject)
    return " ".join(URL_RE.sub("", visible).split())[:SUBJECT_LIMIT].rstrip()


def parse_received(value: str) -> str | None:
    """The date the model reported, re-rendered, or None when it is not one."""
    value = value.strip()
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError:
        pass
    for parse in (datetime.fromisoformat, parsedate_to_datetime):
        try:
            return parse(value).strftime("%Y-%m-%d %H:%M")
        except (ValueError, TypeError, IndexError, AttributeError):
            continue
    return None


def notice(template: str, sender: str, subject: str, received: str, senders: frozenset[str]) -> str | None:
    """The template with the three cleaned fields, or None when the sender is
    not allowlisted or the date does not parse."""
    sender = address(sender)
    received = parse_received(received)
    if sender not in senders or received is None:
        return None
    return template.format(sender=sender, subject=clean_subject(subject), received=received)


def parse_job_output_dir(hermes_home: Path, job_name: str) -> Path:
    data = json.loads((hermes_home / "cron" / "jobs.json").read_text())
    jobs = data.get("jobs", []) if isinstance(data, dict) else data
    ids = [job.get("id") for job in jobs if isinstance(job, dict) and job.get("name") == job_name]
    if len(ids) != 1 or not isinstance(ids[0], str):
        raise LookupError(f"expected one cron job named {job_name!r}, found {len(ids)}")
    return hermes_home / "cron" / "output" / ids[0]


@dataclass
class Pass:
    lines: list[str]
    failures: list[str]
    newly_ledgered: list[tuple[str, str]]
    cursor: str


def run(state: State, output_dir: Path) -> Pass:
    """Everything except Gmail: ledger appends, notices, failures, new cursors."""
    cursor = state.notifier_cursor()
    documents = sorted(p for p in output_dir.glob("*.md") if p.name > cursor) if output_dir.is_dir() else []
    fetched = state.fetched()
    retry = {key for key, at in state.proposal_failures().items() if key in fetched and at >= fetched[key].at}
    ledger = state.ledger()
    senders = state.senders()
    result = Pass([], [], [], cursor)
    for document in documents:
        result.cursor = document.name
        try:
            parsed = parse_block(answer(document.read_text(errors="replace")))
        except NoAnswer:
            continue
        except InvalidBlock as error:
            result.failures.append(f"invalid parse result {document.name}: {error}")
            continue
        new = [
            key
            for key in dict.fromkeys(parsed.processed)
            if key in fetched and key not in ledger and key not in retry
        ]
        notices: dict[str, str | None] = {}
        for entry in parsed.uncertain:
            if entry.key in new and notices.get(entry.key) is None:
                notices[entry.key] = notice(TEMPLATE, entry.sender, entry.subject, entry.received, senders)
        for key in new:
            if (cut := fetched[key].truncated) and notices.get(key) is None:
                notices[key] = notice(TEMPLATE, cut.sender, cut.subject, cut.date, senders)
        held = [key for key, line in notices.items() if line is None]
        result.failures += [
            f"{document.name}: the notice for {key} has no allowlisted sender or no date; left for the next run"
            for key in held
        ]
        new = [key for key in new if key not in held]
        state.append_ledger(new)
        ledger.update(new)
        result.newly_ledgered += [(key, fetched[key].gmail_id) for key in new]
        result.lines += [line for line in notices.values() if line]
    if result.cursor:
        state.set_notifier_cursor(result.cursor)

    quarantined = state.quarantined()
    start = state.quarantine_cursor()
    for number, entry in enumerate(quarantined[start:], start + 1):
        if line := notice(QUARANTINE_TEMPLATE, entry.sender, entry.subject, entry.date, senders):
            result.lines.append(line)
        elif (sender := address(entry.sender)) in senders:
            result.lines.append(UNDATED_QUARANTINE_TEMPLATE.format(sender=sender, subject=clean_subject(entry.subject)))
        else:
            result.failures.append(f"quarantine.txt line {number}: no allowlisted sender")
    state.set_quarantine_cursor(len(quarantined))
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="notifier", description=__doc__.splitlines()[0])
    parser.add_argument("--credential", type=Path, required=True, help="hermes-google-mail JSON")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--hermes-home", type=Path, required=True, help="HERMES_HOME of the gateway")
    parser.add_argument("--run-log", type=Path, help="runs.jsonl for one-line failure rows")
    parser.add_argument("--parse-job", default=PARSE_JOB_NAME)
    args = parser.parse_args(argv)

    state = State(args.state_dir)
    try:
        output_dir = parse_job_output_dir(args.hermes_home, args.parse_job)
    except (OSError, ValueError, LookupError) as error:
        log_failure(args.run_log, JOB_NAME, f"parsing job not found: {error}")
        return 0
    result = run(state, output_dir)
    for failure in result.failures:
        log_failure(args.run_log, JOB_NAME, failure)
    if result.newly_ledgered:
        try:
            gmail = Gmail(Api.from_credential_file(args.credential))
            label_id = gmail.label_id(PROCESSED_LABEL)
            for _key, gmail_id in result.newly_ledgered:
                gmail.add_label(gmail_id, label_id)
        except (GoogleError, OSError) as error:
            log_failure(args.run_log, JOB_NAME, f"labeling {PROCESSED_LABEL} failed: {error}")
    if result.lines:
        print("\n".join(result.lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
