"""x-bookmarks-digest: the weekly X bookmark digest's --script.

Prints the bookmarks the hourly x-bookmarks job found since the last digest (the first time:
in the last seven days), one <bookmark> block each, for the model to summarize. Bookmarks from
the first run or from an import are not new and stay out. Each block goes through Hermes's own
prompt scan; a block the scan rejects is replaced by its link, because Hermes refuses a whole
run whose prompt fails the scan. Without new bookmarks it prints {"wakeAgent": false}, so Hermes
skips the model and sends nothing. After printing blocks it moves digest-cursor, next to the
archive, to now, so a late or repeated run does not send a bookmark twice.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from hermes_family.mailfetch import Scan, ScanError, hermes_scan
from hermes_family.state import write_atomic
from hermes_family.xbookmarks import read_entries

FIRST_WINDOW = timedelta(days=7)
CURSOR_FILE = "digest-cursor"
MAX_BOOKMARKS = 40
TEXT_LIMIT = 1500
QUOTE_LIMIT = 500
MAX_LINKS = 5
# Post text cannot close its block, nor the code fence Hermes puts around script output
# (cron/scheduler_prompt.py:40). Replacing, not deleting, means nested tags cannot reassemble.
TAG_RE = re.compile(r"<(/?)bookmark>", re.IGNORECASE)
FENCE_RE = re.compile(r"`{3,}")
SLEEP = json.dumps({"wakeAgent": False})


def clean(value: object) -> str:
    """Untrusted text, safe to print inside a block."""
    if not isinstance(value, str):
        return ""
    text = value.encode("utf-8", "replace").decode("utf-8")  # a lone surrogate cannot be printed
    text = TAG_RE.sub(r"[\1bookmark]", text)
    return FENCE_RE.sub(lambda match: "'" * len(match.group()), text)


def post_text(post: dict) -> str:
    """The full text: a long post's text is in note_tweet, and `text` is cut."""
    note = post.get("note_tweet")
    if isinstance(note, dict) and isinstance(note.get("text"), str):
        return note["text"]
    return post.get("text") if isinstance(post.get("text"), str) else ""


def _includes(entry: dict, kind: str) -> list[dict]:
    includes = entry.get("includes")
    items = includes.get(kind) if isinstance(includes, dict) else None
    return [item for item in items or [] if isinstance(item, dict)]


def author(entry: dict) -> dict:
    users = _includes(entry, "users")
    return users[0] if users else {}


def link(entry: dict) -> str:
    username = author(entry).get("username")
    if isinstance(username, str) and re.fullmatch(r"\w{1,15}", username):
        return f"https://x.com/{username}/status/{entry['id']}"
    return f"https://x.com/i/web/status/{entry['id']}"


def quoted_posts(entry: dict) -> list[dict]:
    post = entry.get("post") or {}
    ids = {
        ref.get("id") for ref in post.get("referenced_tweets") or []
        if isinstance(ref, dict) and ref.get("type") == "quoted"
    }
    return [tweet for tweet in _includes(entry, "tweets") if tweet.get("id") in ids]


def host_of(url: object) -> str:
    match = re.match(r"https?://(?:www\.)?([^/:?#]+)", url) if isinstance(url, str) else None
    return match.group(1).lower() if match else ""


def outside_links(post: dict) -> list[str]:
    """Expanded links in the post, without X's own links to the post, its media or a quote."""
    entities = post.get("entities") if isinstance(post.get("entities"), dict) else {}
    urls: list[str] = []
    for item in entities.get("urls") or []:
        url = clean(item.get("expanded_url")) if isinstance(item, dict) else ""
        if host_of(url) not in ("", "x.com", "twitter.com") and url not in urls:
            urls.append(url)
    return urls[:MAX_LINKS]


def block(entry: dict) -> str:
    post = entry.get("post") if isinstance(entry.get("post"), dict) else {}
    who = author(entry)
    lines = ["<bookmark>", f"Link: {link(entry)}"]
    if who.get("username"):
        name = f" ({clean(who.get('name'))})" if who.get("name") else ""
        lines.append(f"Author: @{clean(who['username'])}{name}")
    if isinstance(post.get("created_at"), str):
        lines.append(f"Posted: {clean(post['created_at'])}")
    lines += ["Text:", clean(post_text(post))[:TEXT_LIMIT]]
    for quoted in quoted_posts(entry):
        lines += ["Quoted post:", clean(post_text(quoted))[:QUOTE_LIMIT]]
    links = outside_links(post)
    if links:
        lines.append(f"Links: {' '.join(links)}")
    lines.append("</bookmark>")
    return "\n".join(lines)


def seen_at(entry: dict) -> datetime | None:
    try:
        moment = datetime.fromisoformat(entry.get("first_seen_at") or "")
    except (TypeError, ValueError):
        return None
    return moment if moment.tzinfo else None


def render(entries: list[dict], since: datetime, now: datetime, scan: Scan) -> str:
    recent = [
        entry for entry in entries
        if entry.get("via") == "poll" and (moment := seen_at(entry)) is not None and since < moment <= now
    ]
    if not recent:
        return SLEEP
    shown = recent[-MAX_BOOKMARKS:]
    blocks = [block(entry) for entry in shown]
    parts, hidden = [], []
    for entry, text, error in zip(shown, blocks, scan(blocks), strict=True):
        if error:
            hidden.append(link(entry))
        else:
            parts.append(text)
    if len(recent) > len(shown):
        parts.append(f"Only the newest {len(shown)} of the {len(recent)} new bookmarks are shown.")
    if hidden:
        parts.append(f"Not shown, because Hermes's prompt scan rejected their text: {' '.join(hidden)}")
    return "\n\n".join(parts)


def read_cursor(path: Path, now: datetime) -> datetime:
    """Where the last digest's window ended; without one, FIRST_WINDOW before now."""
    try:
        moment = datetime.fromisoformat(path.read_text().strip())
    except (FileNotFoundError, ValueError):
        return now - FIRST_WINDOW
    return moment if moment.tzinfo else now - FIRST_WINDOW


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="x-bookmarks-digest", description=__doc__.splitlines()[0])
    parser.add_argument("--archive", type=Path, required=True, help="the x-bookmarks bookmarks.jsonl")
    parser.add_argument("--hermes-python", required=True, help="the Python of the installed Hermes, for its prompt scan")
    args = parser.parse_args(argv)
    cursor = args.archive.parent / CURSOR_FILE
    now = datetime.now(timezone.utc)
    try:
        output = render(read_entries(args.archive), read_cursor(cursor, now), now, hermes_scan(args.hermes_python))
        print(output)
        if output != SLEEP:
            write_atomic(cursor, now.isoformat() + "\n")
    except (ScanError, OSError) as error:
        print(f"x-bookmarks-digest: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
