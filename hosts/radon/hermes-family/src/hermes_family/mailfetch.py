"""mail-fetch: the parsing job's --script. The only way mail reaches a model.

Lists inbox mail without a hermes label. A sender outside senders.txt gets
`hermes-ignored` and is never printed; a key already in the ledger gets
`hermes-processed` and is skipped. Every other mail is printed as one block,
`Mail-Key:` first. The printed keys go to the fetch record, so the notifier
only accepts keys this script showed the model. Empty output makes Hermes
skip the model call.
"""

from __future__ import annotations

import argparse
import base64
import re
import sys
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterator

from hermes_family.google import Api, Gmail
from hermes_family.state import IGNORED_LABEL, PROCESSED_LABEL, State, address, mail_key

QUERY = f"in:inbox -label:{PROCESSED_LABEL} -label:{IGNORED_LABEL}"
BODY_LIMIT_BYTES = 8 * 1024
LIST_LIMIT = 200
MAIL_TAG_RE = re.compile(r"<(/?)mail>", re.IGNORECASE)
CHARSET_RE = re.compile(r'charset="?([^";\s]+)', re.IGNORECASE)
BLOCK_TAGS = {"p", "br", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "table"}


class _HtmlText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.chunks: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style"}:
            self._skip += 1
        elif tag in BLOCK_TAGS:
            self.chunks.append("\n")

    def handle_endtag(self, tag):
        if tag in {"script", "style"} and self._skip:
            self._skip -= 1
        elif tag in BLOCK_TAGS:
            self.chunks.append("\n")

    def handle_data(self, data):
        if not self._skip:
            self.chunks.append(data)


def html_to_text(html: str) -> str:
    parser = _HtmlText()
    parser.feed(html)
    lines = (" ".join(line.split()) for line in "".join(parser.chunks).splitlines())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def _parts(part: dict[str, Any]) -> Iterator[dict[str, Any]]:
    yield part
    for child in part.get("parts") or []:
        yield from _parts(child)


def _part_text(part: dict[str, Any]) -> str:
    raw = base64.urlsafe_b64decode(part["body"]["data"] + "=" * (-len(part["body"]["data"]) % 4))
    content_type = next(
        (h.get("value", "") for h in part.get("headers") or [] if h.get("name", "").lower() == "content-type"), ""
    )
    match = CHARSET_RE.search(content_type)
    try:
        return raw.decode(match.group(1) if match else "utf-8", errors="replace")
    except LookupError:
        return raw.decode("utf-8", errors="replace")


def plain_text(payload: dict[str, Any]) -> str:
    """The text/plain parts, or the text/html parts as text. Attachments are skipped."""
    inline = [p for p in _parts(payload) if not p.get("filename") and (p.get("body") or {}).get("data")]
    for mime in ("text/plain", "text/html"):
        texts = [_part_text(p) for p in inline if p.get("mimeType") == mime]
        if texts:
            text = "\n\n".join(texts).replace("\r\n", "\n")
            return html_to_text(text) if mime == "text/html" else text.strip()
    return ""


def cut(text: str, limit: int = BODY_LIMIT_BYTES) -> str:
    return text.encode()[:limit].decode("utf-8", errors="ignore")


def headers(message: dict[str, Any]) -> dict[str, str]:
    found: dict[str, str] = {}
    for header in (message.get("payload") or {}).get("headers") or []:
        found.setdefault(header.get("name", "").lower(), header.get("value", ""))
    return found


def _field(value: str) -> str:
    return MAIL_TAG_RE.sub(r"[\1mail]", " ".join(value.split()))


def block(key: str, head: dict[str, str], body: str) -> str:
    """One mail as the model sees it. Mail text cannot close or open a block."""
    return "\n".join(
        [
            "<mail>",
            f"Mail-Key: {key}",
            f"Message-ID: {_field(head.get('message-id', ''))}",
            f"From: {_field(head.get('from', ''))}",
            f"Date: {_field(head.get('date', ''))}",
            f"Subject: {_field(head.get('subject', ''))}",
            "",
            MAIL_TAG_RE.sub(r"[\1mail]", cut(body)),
            "</mail>",
        ]
    )


def fetch(gmail: Gmail, state: State, *, dry_run: bool, max_mails: int, now: datetime) -> list[str]:
    senders = state.senders()
    ledger = state.ledger()
    label_ids: dict[str, str] = {}

    def label(message_id: str, name: str) -> None:
        if dry_run:
            return
        if name not in label_ids:
            label_ids[name] = gmail.label_id(name)
        gmail.add_label(message_id, label_ids[name])

    blocks: list[str] = []
    printed: dict[str, str] = {}
    for gmail_id in gmail.message_ids(QUERY, LIST_LIMIT):
        message = gmail.message(gmail_id)
        head = headers(message)
        message_id = head.get("message-id", "").strip()
        if address(head.get("from", "")) not in senders:
            label(gmail_id, IGNORED_LABEL)
            continue
        if not message_id:
            print(f"mail-fetch: {gmail_id} has no Message-ID; labeled {IGNORED_LABEL}", file=sys.stderr)
            label(gmail_id, IGNORED_LABEL)
            continue
        key = mail_key(message_id)
        if key in ledger:
            label(gmail_id, PROCESSED_LABEL)
            continue
        if key in printed or len(printed) >= max_mails:
            continue
        printed[key] = gmail_id
        blocks.append(block(key, head, plain_text(message.get("payload") or {})))
    if printed and not dry_run:
        state.record_fetch(printed, now)
    return blocks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="mail-fetch", description=__doc__.splitlines()[0])
    parser.add_argument("--credential", type=Path, required=True, help="hermes-google-mail JSON")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--max-mails", type=int, default=10, help="mails printed per run")
    parser.add_argument("--dry-run", action="store_true", help="print only: no labels, no fetch record")
    args = parser.parse_args(argv)

    gmail = Gmail(Api.from_credential_file(args.credential))
    blocks = fetch(
        gmail, State(args.state_dir), dry_run=args.dry_run, max_mails=args.max_mails, now=datetime.now(timezone.utc)
    )
    if blocks:
        print("\n\n".join(blocks))
    return 0


if __name__ == "__main__":
    sys.exit(main())
