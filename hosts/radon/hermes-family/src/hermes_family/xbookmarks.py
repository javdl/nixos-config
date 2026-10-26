"""x-bookmarks: copy Joost's X bookmarks into an append-only archive, as a no-agent cron job.

Each run first asks X for the ids of the newest bookmarks only: an owned read with no
expansions, which X bills once per post per UTC day. When one of those ids is not in the
archive, it fetches the posts down to the last unknown one with their text, author, media and
referenced posts, and appends one JSON line per new bookmark, oldest first. When one of the
two oldest of them is new too, it walks pages of 90 until a page ends with two known posts. An
empty archive so gets every bookmark the API still returns: X documents 800, and its
pagination has been seen to stop near 200.

A twitter-web-exporter JSON export in --import-dir adds the bookmarks the API no longer
returns. Each export is read once (its SHA-256 goes to imported.txt next to the archive) and
adds only post ids the archive does not have.

stdout is what Hermes sends: nothing after an ordinary run, a line after the first run or an
import. A failure exits 1 with the reason on stderr, and Hermes sends that as an alert. The
credential is OAuth 1.0a, whose tokens never refresh, so two clients cannot invalidate each
other's tokens. Nothing here prints a credential.
"""

from __future__ import annotations

import argparse
import base64
import fcntl
import hashlib
import hmac
import http.client
import json
import os
import re
import secrets
import sys
import time
import urllib.parse
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from hermes_family import net

API = "https://api.x.com/2"
PROBE_SIZE = 10
WALK_SIZE = 90
MAX_PAGES = 12
# A page or the probe must end with this many known posts before capture stops: a single
# known post can be an archived post that was bookmarked again, with new ones below it.
STOP_RUN = 2
POST_FIELDS = (
    "created_at,author_id,conversation_id,lang,entities,attachments,referenced_tweets,"
    "note_tweet,article,public_metrics,possibly_sensitive"
)
EXPANSIONS = "author_id,attachments.media_keys,referenced_tweets.id"
USER_FIELDS = "username,name"
MEDIA_FIELDS = "type,url,preview_image_url,alt_text,variants"
CREDENTIAL_KEYS = ("X_API_KEY", "X_API_KEY_SECRET", "X_ACCESS_TOKEN", "X_ACCESS_TOKEN_SECRET", "X_USER_ID")
ID_RE = re.compile(r"\d{1,19}")
IMPORTED_FILE = "imported.txt"
BACKFILL_MARKER = "backfilled"
LOCK_FILE = ".lock"


@contextmanager
def archive_lock(archive: Path) -> Iterator[None]:
    """Held while x-bookmarks stamps and appends, and while the digest reads and moves its
    cursor, so a digest never runs between a capture's timestamp and its append."""
    archive.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (archive.parent / LOCK_FILE).open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


class XError(RuntimeError):
    pass


@dataclass(frozen=True, repr=False)
class Credential:
    api_key: str
    api_key_secret: str
    access_token: str
    access_token_secret: str
    user_id: str


def load_credential(path: Path) -> Credential:
    """The hermes-x-bookmarks dotenv. An error names missing keys, never values."""
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        name, separator, value = line.partition("=")
        if separator:
            values[name.strip()] = value.strip()
    missing = [name for name in CREDENTIAL_KEYS if not values.get(name)]
    if missing:
        raise XError(f"{path} lacks {', '.join(missing)}")
    if not ID_RE.fullmatch(values["X_USER_ID"]):
        raise XError(f"{path}: X_USER_ID is not a numeric account id")
    return Credential(*(values[name] for name in CREDENTIAL_KEYS))


def _enc(value: str) -> str:
    return urllib.parse.quote(value, safe="-._~")


def oauth1_header(
    method: str,
    url: str,
    params: dict[str, str],
    credential: Credential,
    *,
    nonce: str | None = None,
    timestamp: int | None = None,
) -> str:
    """HMAC-SHA1 OAuth 1.0a Authorization header for a request whose query or form
    parameters are `params` (docs.x.com, "Creating a signature")."""
    oauth = {
        "oauth_consumer_key": credential.api_key,
        "oauth_nonce": nonce or secrets.token_hex(16),
        "oauth_signature_method": "HMAC-SHA1",
        "oauth_timestamp": str(int(time.time()) if timestamp is None else timestamp),
        "oauth_token": credential.access_token,
        "oauth_version": "1.0",
    }
    pairs = sorted((_enc(name), _enc(value)) for name, value in {**params, **oauth}.items())
    base = "&".join((method.upper(), _enc(url), _enc("&".join(f"{name}={value}" for name, value in pairs))))
    key = f"{_enc(credential.api_key_secret)}&{_enc(credential.access_token_secret)}"
    oauth["oauth_signature"] = base64.b64encode(hmac.new(key.encode(), base.encode(), hashlib.sha1).digest()).decode()
    return "OAuth " + ", ".join(f'{_enc(name)}="{_enc(value)}"' for name, value in sorted(oauth.items()))


@dataclass(frozen=True)
class Page:
    posts: list[dict]
    includes: dict
    next_token: str | None


def _problem(body: object) -> str:
    if not isinstance(body, dict):
        return ""
    parts = [str(body[key]).strip() for key in ("title", "detail") if body.get(key)]
    return f": {' - '.join(parts)}"[:300] if parts else ""


class Bookmarks:
    """GET /2/users/:id/bookmarks, newest bookmark first."""

    def __init__(self, credential: Credential):
        self.credential = credential
        self.url = f"{API}/users/{credential.user_id}/bookmarks"

    def page(self, size: int, token: str | None = None, *, detailed: bool) -> Page:
        params = {"max_results": str(size)}
        if token:
            params["pagination_token"] = token
        if detailed:
            params.update({
                "tweet.fields": POST_FIELDS,
                "expansions": EXPANSIONS,
                "user.fields": USER_FIELDS,
                "media.fields": MEDIA_FIELDS,
            })
        header = oauth1_header("GET", self.url, params, self.credential)
        response = net.send("GET", self.url, params=params, headers={"Authorization": header})
        try:
            body = response.json()
        except ValueError:
            body = None
        if not response.ok or not isinstance(body, dict):
            raise XError(f"X answered HTTP {response.status}{_problem(body)}")
        posts = [
            post for post in body.get("data") or []
            if isinstance(post, dict) and isinstance(post.get("id"), str) and ID_RE.fullmatch(post["id"])
        ]
        includes = body.get("includes") if isinstance(body.get("includes"), dict) else {}
        meta = body.get("meta") if isinstance(body.get("meta"), dict) else {}
        token = meta.get("next_token")
        return Page(posts, includes, token if isinstance(token, str) and token else None)


def includes_for(post: dict, includes: dict) -> dict:
    """The page's expanded objects that this post refers to."""
    wanted = {
        ("users", "id"): {post.get("author_id")},
        ("media", "media_key"): set((post.get("attachments") or {}).get("media_keys") or []),
        ("tweets", "id"): {ref.get("id") for ref in post.get("referenced_tweets") or [] if isinstance(ref, dict)},
    }
    selected = {}
    for (kind, key), ids in wanted.items():
        items = [item for item in includes.get(kind) or [] if isinstance(item, dict) and item.get(key) in ids]
        if items:
            selected[kind] = items
    return selected


def ends_unknown(posts: list[dict], known: set[str]) -> bool:
    """Whether new bookmarks may continue past this page: it shows fewer than STOP_RUN posts,
    or one of its last STOP_RUN posts is new."""
    return len(posts) < STOP_RUN or any(post["id"] not in known for post in posts[-STOP_RUN:])


def walk(api: Bookmarks, known: set[str]) -> tuple[list[Page], bool]:
    """Detailed pages from the newest bookmark down to the first page that ends with STOP_RUN
    known posts. The bool says whether MAX_PAGES stopped it while X had more."""
    pages: list[Page] = []
    token = None
    while True:
        page = api.page(WALK_SIZE, token, detailed=True)
        pages.append(page)
        if not page.next_token or not ends_unknown(page.posts, known):
            return pages, False
        if len(pages) == MAX_PAGES:
            return pages, True
        token = page.next_token


def _entry(post: dict, includes: dict, now: str, via: str) -> dict:
    return {"id": post["id"], "first_seen_at": now, "via": via, "post": post, "includes": includes}


def capture(api: Bookmarks, known: set[str], now: str, via: str) -> tuple[list[dict], bool]:
    """New archive entries, newest first, marked `via`; and whether a walk was cut off by
    MAX_PAGES."""
    probe = api.page(PROBE_SIZE, detailed=False)
    unknown = [post for post in probe.posts if post["id"] not in known]
    if not unknown and not (probe.next_token and ends_unknown(probe.posts, known)):
        return [], False  # a probe that shows too little to end on two known posts walks
    truncated = False
    if probe.next_token and ends_unknown(probe.posts, known):
        pages, truncated = walk(api, known)
    else:
        last = max(index for index, post in enumerate(probe.posts) if post["id"] not in known)
        pages = [api.page(last + 1, detailed=True)]
        returned = {post["id"] for post in pages[0].posts}
        if any(post["id"] not in returned for post in unknown):
            # The page held fewer of the probe's posts than it counted: a bookmark added since
            # the probe, or one X counts but no longer shows. Walk from the top instead.
            pages, truncated = walk(api, known)
    entries: list[dict] = []
    seen: set[str] = set()
    for page in pages:
        for post in page.posts:
            if post["id"] in known or post["id"] in seen:
                continue
            seen.add(post["id"])
            entries.append(_entry(post, includes_for(post, page.includes), now, via))
    # A probe post that no detailed page returned is stored as the probe saw it (id and
    # text), so it is neither lost nor fetched again on every run.
    rank = {post["id"]: index for index, post in enumerate(probe.posts)}
    for post in unknown:
        if post["id"] not in seen:
            _place(entries, _entry(post, {}, now, via), rank)
    return entries, truncated


def _place(entries: list[dict], entry: dict, rank: dict[str, int]) -> None:
    """Insert a probe post into the newest-first entries where the probe's order puts it:
    before the first entry the probe saw below it, else after the last it saw above it, else
    first, since the probe holds the newest bookmarks."""
    mine = rank[entry["id"]]
    for index, other in enumerate(entries):
        if rank.get(other["id"], -1) > mine:
            entries.insert(index, entry)
            return
    above = [index for index, other in enumerate(entries) if other["id"] in rank]
    entries.insert(above[-1] + 1 if above else 0, entry)


def read_entries(path: Path) -> list[dict]:
    """Archive entries in file order. A line a crash cut short is skipped, so its post
    counts as unknown and is fetched again."""
    try:
        # Not splitlines(): it also splits at U+2028, U+2029 and U+0085, which JSON allows raw.
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    except FileNotFoundError:
        return []
    entries = []
    for line in lines:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(entry, dict) and isinstance(entry.get("id"), str):
            entries.append(entry)
    return entries


def append_entries(path: Path, entries: list[dict]) -> None:
    if not entries:
        return
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    text = "".join(json.dumps(entry, sort_keys=True) + "\n" for entry in entries)
    with path.open("a+b") as handle:
        handle.seek(0, os.SEEK_END)
        if handle.tell():
            handle.seek(-1, os.SEEK_END)
            if handle.read(1) != b"\n":
                text = "\n" + text
        handle.write(text.encode("utf-8"))
        handle.flush()
        os.fsync(handle.fileno())


def parse_export(data: bytes) -> list[dict]:
    """A twitter-web-exporter JSON export: a list of objects with a string post `id`."""
    records = json.loads(data)
    if not isinstance(records, list) or not records:
        raise ValueError("it is not a list of posts")
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("id"), str) or not ID_RE.fullmatch(record["id"]):
            raise ValueError("an item has no numeric post id")
    return records


def import_exports(import_dir: Path, archive: Path, known: set[str], now: str) -> list[str]:
    """Append the unknown posts of each export not imported before; one line per export."""
    if not import_dir.is_dir():
        return []
    done_file = archive.parent / IMPORTED_FILE
    try:
        done = set(done_file.read_text(encoding="utf-8").split())
    except FileNotFoundError:
        done = set()
    lines = []
    for path in sorted(import_dir.glob("*.json")):
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest in done:
            continue
        try:
            records = parse_export(data)
        except ValueError as error:
            lines.append(f"X bookmarks: {path.name} is not a twitter-web-exporter JSON export ({error}); not imported.")
        else:
            entries = []
            for record in records:
                if record["id"] not in known:
                    known.add(record["id"])
                    entries.append({"id": record["id"], "first_seen_at": now, "via": "import", "post": record})
            append_entries(archive, entries)
            lines.append(
                f"X bookmarks: imported {len(entries)} bookmarks from {path.name}; "
                f"{len(records) - len(entries)} were already in the archive."
            )
        archive.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with done_file.open("a", encoding="utf-8") as handle:
            handle.write(f"{digest}  {path.name}\n")
        done.add(digest)
    return lines


def stamp(moment: datetime) -> str:
    """first_seen_at, to the microsecond like the digest cursor: a capture that takes the lock
    right after a digest, in the same second, must not be stamped before that cursor."""
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


CAUGHT = (XError, OSError, http.client.HTTPException)


def capture_into(archive: Path, credential: Path, known: set[str], now: str, import_dir: Path | None) -> list[str]:
    """Capture and append. The first successful capture is the backfill, even if it finds
    nothing or an import came first; BACKFILL_MARKER records that it happened."""
    marker = archive.parent / BACKFILL_MARKER
    first = not marker.exists()
    entries, truncated = capture(Bookmarks(load_credential(credential)), known, now, "backfill" if first else "poll")
    append_entries(archive, entries[::-1])
    known.update(entry["id"] for entry in entries)
    if not first:
        return []
    marker.write_text(f"{now}\n")
    lines = [f"X bookmarks: the first run stored the {len(entries)} bookmarks that X's API returned."]
    if truncated:
        lines.append(f"It stopped after {MAX_PAGES} pages of {WALK_SIZE}; X may hold more.")
    if import_dir:
        lines.append(f"For older ones, put a twitter-web-exporter JSON export in {import_dir}.")
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="x-bookmarks", description=__doc__.splitlines()[0])
    parser.add_argument("--credential", type=Path, required=True, help="hermes-x-bookmarks dotenv")
    parser.add_argument("--archive", type=Path, required=True, help="the append-only bookmarks.jsonl")
    parser.add_argument("--import-dir", type=Path, help="folder for twitter-web-exporter JSON exports")
    args = parser.parse_args(argv)

    lines: list[str] = []
    errors: list[str] = []
    try:
        with archive_lock(args.archive):
            now = stamp(datetime.now(timezone.utc))
            known = {entry["id"] for entry in read_entries(args.archive)}
            try:
                lines += capture_into(args.archive, args.credential, known, now, args.import_dir)
            except CAUGHT as error:
                errors.append(str(error))  # an X outage does not hold back a queued export
            if args.import_dir:
                lines += import_exports(args.import_dir, args.archive, known, now)
    except CAUGHT as error:
        errors.append(str(error))
    if lines:
        print("\n".join(lines))
    for error in errors:
        print(f"x-bookmarks: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
