"""notifier: the only path from the mail-parsing job to the family group.

A no-agent cron job, so Hermes delivers its stdout to the job's --deliver
target and an empty stdout sends nothing. It reads the parsing job's run
documents newer than its cursor, takes the last fenced JSON block of each
model answer, ledgers and labels the processed keys that mail-fetch printed,
and prints the fixed template for each valid uncertain mail. Model text never
reaches the output: every printed field is re-derived or sanitized.
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


def notice(entry: Uncertain, senders: frozenset[str]) -> str | None:
    sender = address(entry.sender)
    received = parse_received(entry.received)
    subject = clean_subject(entry.subject)
    if sender not in senders or received is None:
        return None
    return TEMPLATE.format(sender=sender, subject=subject, received=received)


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
    """Everything except Gmail: ledger appends, notices, failures, new cursor."""
    cursor = state.notifier_cursor()
    documents = sorted(p for p in output_dir.glob("*.md") if p.name > cursor) if output_dir.is_dir() else []
    fetched = state.fetched()
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
            result.failures.append(f"{document.name}: {error}")
            continue
        new = [key for key in dict.fromkeys(parsed.processed) if key in fetched and key not in ledger]
        state.append_ledger(new)
        ledger.update(new)
        result.newly_ledgered += [(key, fetched[key]) for key in new]
        notified = set()
        for entry in parsed.uncertain:
            if entry.key in new and entry.key not in notified and (line := notice(entry, senders)):
                notified.add(entry.key)
                result.lines.append(line)
    if result.cursor:
        state.set_notifier_cursor(result.cursor)
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
        log_failure(args.run_log, JOB_NAME, f"invalid parse result {failure}")
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
