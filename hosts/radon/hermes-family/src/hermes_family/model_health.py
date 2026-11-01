"""One independent model-route check, with direct Telegram DM incident delivery."""

from __future__ import annotations

import argparse
import dataclasses
import fcntl
import json
import math
import os
import re
import shlex
import signal
import sys
import time
from contextlib import contextmanager
from http.client import HTTPException
from pathlib import Path

from . import net
from .state import write_atomic

FAILURE_GRACE_S = 900
PROBE_TIMEOUT_S = 45
TELEGRAM_BASE = "https://api.telegram.org"


@dataclasses.dataclass
class Health:
    failure_since: float | None = None
    alerted: bool = False
    retry_at: float = 0


@contextmanager
def deadline(seconds):
    def expired(*_):
        raise TimeoutError("model-health deadline exceeded")

    previous = signal.signal(signal.SIGALRM, expired)
    remaining, interval = signal.getitimer(signal.ITIMER_REAL)
    started = time.monotonic()
    signal.setitimer(signal.ITIMER_REAL, min(seconds, remaining) if remaining else seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
        if remaining:
            signal.setitimer(signal.ITIMER_REAL, max(0.001, remaining - (time.monotonic() - started)), interval)


def credentials(env_file: Path, family_file: Path) -> tuple[str, str]:
    values = {}
    for line in env_file.read_text().splitlines():
        key, sep, value = line.removeprefix("export ").partition("=")
        if sep and key.strip() in ("TELEGRAM_BOT_TOKEN", "TELEGRAM_ALLOWED_USERS"):
            parts = shlex.split(value, comments=True)
            if len(parts) != 1 or key.strip() in values:
                raise ValueError("invalid Telegram environment")
            values[key.strip()] = parts[0]
    token = values.get("TELEGRAM_BOT_TOKEN", "")
    target = json.loads(family_file.read_text()).get("personal_deliver", "")
    if not isinstance(target, str) or not re.fullmatch(r"telegram:[1-9][0-9]*", target):
        raise ValueError("a private Telegram user target is required")
    chat = target.partition(":")[2]
    if not re.fullmatch(r"[0-9]+:[A-Za-z0-9_-]+", token) or chat not in {
        user.strip() for user in values.get("TELEGRAM_ALLOWED_USERS", "").split(",")
    }:
        raise ValueError("invalid bot token or unallowlisted user")
    return token, chat


def probe(base_url: str, model: str) -> bool:
    try:
        with deadline(PROBE_TIMEOUT_S):
            response = net.send_json("POST", f"{base_url.rstrip('/')}/chat/completions", {
                "model": model, "reasoning_effort": "high", "max_tokens": 1024,
                "messages": [{"role": "user", "content": "Reply with only OK."}],
            }, follow_redirects=False)
            body = response.json()
            return (response.ok and body.get("model") in (model, model.rsplit("/", 1)[-1])
                    and bool(body["choices"][0]["message"]["content"].strip()))
    except (OSError, HTTPException, ValueError, TypeError, KeyError, IndexError, AttributeError):
        return False


def notify(token: str, chat: str, text: str) -> tuple[bool, int]:
    for method, payload in (
        ("getChat", {"chat_id": chat}),
        ("sendMessage", {"chat_id": chat, "text": text}),
    ):
        response = net.send_json("POST", f"{TELEGRAM_BASE}/bot{token}/{method}", payload,
                                 follow_redirects=False)
        body = response.json()
        if not response.ok or body.get("ok") is not True:
            delay = body.get("parameters", {}).get("retry_after", 0)
            return False, delay if type(delay) is int and delay > 0 else 0
        result = body["result"] if method == "getChat" else body["result"]["chat"]
        if result.get("type") != "private" or result.get("id") != int(chat):
            return False, 0
    return True, 0


def check(args) -> int:
    token, chat = credentials(args.env_file, args.family)
    args.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = args.state_dir / "model-health.json"
    with (args.state_dir / "model-health.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            health = Health(**json.loads(path.read_text()))
        except FileNotFoundError:
            health = Health()
        if (type(health.alerted) is not bool
                or any(type(value) not in (int, float) or not math.isfinite(value)
                       for value in (health.retry_at, 0 if health.failure_since is None else health.failure_since))):
            raise ValueError("invalid health state")
        now = time.time()
        healthy = probe(args.base_url, args.model)
        if healthy and not health.alerted:
            health = Health(retry_at=health.retry_at)
        elif not healthy and health.failure_since is None:
            health.failure_since = now
        write_atomic(path, json.dumps(dataclasses.asdict(health)))
        due = (healthy and health.alerted) or (
            not healthy and not health.alerted and now - health.failure_since >= FAILURE_GRACE_S)
        if not due or now < health.retry_at:
            return 0
        text = (f"Hermes: {args.model} is weer bereikbaar via Aperture vanaf radon."
                if healthy else f"Hermes: {args.model} is al minstens 15 minuten niet bereikbaar "
                "via Aperture vanaf radon. Geen herstart of rollback uitgevoerd.")
        sent, retry_after = notify(token, chat, text)
        if sent:
            health = Health() if healthy else dataclasses.replace(health, alerted=True, retry_at=0)
        else:
            health.retry_at = time.time() + retry_after
        write_atomic(path, json.dumps(dataclasses.asdict(health)))
        if not sent:
            print("model-health: Telegram delivery failed; will retry", file=sys.stderr)
        return 0 if sent else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path, required=True)
    parser.add_argument("--family", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", required=True)
    args = parser.parse_args(argv)
    os.umask(0o077)
    # Bound the whole invocation, including readiness-independent network reads
    # and lock acquisition, rather than only each socket's inactivity timeout.
    try:
        with deadline(120):
            return check(args)
    except (OSError, HTTPException, ValueError, TypeError, KeyError, AttributeError):
        # urllib exceptions can contain a Telegram URL with the bot token.
        print("model-health: configuration, state or delivery check failed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
