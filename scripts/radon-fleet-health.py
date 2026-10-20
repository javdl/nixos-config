#!/usr/bin/env python3
"""Read-only fleet health probe for radon.

Curls a fixed set of endpoints with short timeouts, plus a few local checks,
and writes one JSON snapshot. It does not restart services, listen on the
network, read Hermes secrets, or contact the work tailnet (stargazer-duck).

spark's vLLM port is reached through tailscale serve. The personal tailnet
policy may drop tag:hermes to spark:8443. When spark's Ollama port answers
and :8443 times out, the check records "not reachable by policy" and leaves
the policy unchanged.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path


POLICY_ERROR = "not reachable by policy"
FORBIDDEN_USERS = frozenset({"root", "hermes"})
CONNECT_TIMEOUT_SECONDS = "3"
MAX_TIME_SECONDS = "5"
LAST_LINE_LIMIT = 400

# Personal tailnet (buri-hoki) only. No stargazer-duck / bali names.
HTTP_CHECKS = (
    {
        "name": "spark_ollama",
        "url": "http://spark.buri-hoki.ts.net:11434/v1/models",
        "kind": "http_2xx",
    },
    {
        "name": "spark_vllm",
        "url": "https://spark.buri-hoki.ts.net:8443/health",
        "kind": "http_2xx",
    },
    {
        "name": "spark2_ollama",
        "url": "http://spark2.buri-hoki.ts.net:11434/v1/models",
        "kind": "http_2xx",
    },
    {
        "name": "j9_ollama",
        "url": "http://j9.buri-hoki.ts.net:11434/v1/models",
        "kind": "http_2xx",
    },
    {
        "name": "radon_hermes_webui",
        "url": "http://127.0.0.1:8787/",
        "kind": "http_any",
    },
    {
        "name": "radon_ollama",
        "url": "http://127.0.0.1:11434/v1/models",
        "kind": "http_2xx",
    },
    {
        "name": "aperture",
        "url": "https://ai.buri-hoki.ts.net/v1/models",
        "kind": "http_any",
    },
)


def curl_argv(curl_bin: str, url: str) -> list[str]:
    """Status and timing only. -q ignores ~/.curlrc so a netrc cannot attach credentials."""
    return [
        curl_bin,
        "-q",
        "--silent",
        "--show-error",
        "--ipv4",
        "--output",
        "/dev/null",
        "--connect-timeout",
        CONNECT_TIMEOUT_SECONDS,
        "--max-time",
        MAX_TIME_SECONDS,
        "--write-out",
        "%{http_code}",
        "--url",
        url,
    ]


def check(ok: bool, status, latency: int, error) -> dict:
    return {
        "ok": ok,
        "status": status,
        "latency": latency,
        "error": error,
    }


def interpret_http(kind: str, returncode: int, stdout: str, stderr: str, latency: int) -> dict:
    code_text = (stdout or "").strip()
    status = int(code_text) if code_text.isdigit() and code_text != "000" else None
    if returncode != 0 or status is None:
        detail = (stderr or "curl failed").strip().splitlines()
        error = (detail[-1] if detail else "curl failed")[:300]
        return check(False, None, latency, error)
    if kind == "http_any" or 200 <= status < 300:
        return check(True, status, latency, None)
    return check(False, status, latency, f"HTTP {status}")


def is_timeout(error: str | None) -> bool:
    text = (error or "").lower()
    return "timed out" in text or "timeout" in text


def classify_vllm(vllm: dict, spark_ollama: dict) -> dict:
    """Rewrite a timeout as a policy result only when spark itself answered.

    Tailscale ACL drops time out. Connection refused means the host was
    reached and nothing is listening, which is a different failure and stays
    as the curl error. An HTTP status means the port was allowed.
    """
    if vllm.get("status") is not None:
        return vllm
    if spark_ollama.get("status") is None or not is_timeout(vllm.get("error")):
        return vllm
    classified = dict(vllm)
    classified["ok"] = False
    classified["error"] = POLICY_ERROR
    classified["detail"] = vllm.get("error")
    return classified


def parse_mount(mount_text: str, volume: str) -> bool:
    needle = f" on {volume} ("
    return any(needle in line for line in mount_text.splitlines())


def parse_df(df_text: str, mountpoint: str) -> int | None:
    for line in df_text.splitlines()[1:]:
        fields = line.split()
        if len(fields) < 4 or fields[-1] != mountpoint:
            continue
        try:
            return int(fields[3]) * 1024
        except ValueError:
            return None
    return None


def parse_launchctl_exit(text: str | None) -> int | None:
    if not text:
        return None
    marker = "last exit code = "
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(marker):
            value = stripped[len(marker) :].strip()
            if value.isdigit():
                return int(value)
    return None


def last_nonempty_line(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return ""
    return lines[-1][:LAST_LINE_LIMIT]


def looks_like_failure(last_line: str) -> bool:
    lowered = last_line.lower()
    return lowered.startswith("error:") or " error:" in f" {lowered}"


def agent_volume_check(mount_text: str, volume: str, latency: int) -> dict:
    mounted = parse_mount(mount_text, volume)
    if mounted:
        return check(True, "mounted", latency, None)
    return check(False, "absent", latency, f"{volume} is not mounted")


def disk_check(df_text: str, mountpoint: str, latency: int) -> dict:
    free_bytes = parse_df(df_text, mountpoint)
    if free_bytes is None:
        result = check(False, None, latency, f"could not parse df for {mountpoint}")
        result["free_bytes"] = None
        return result
    # Measurement only. The reader decides what is low.
    result = check(True, free_bytes, latency, None)
    result["free_bytes"] = free_bytes
    return result


def auto_update_check(log_text: str | None, log_error: str | None, launchctl_text: str | None, latency: int) -> dict:
    exit_code = parse_launchctl_exit(launchctl_text)
    if log_error:
        result = check(False, exit_code, latency, log_error)
        result["last_line"] = None
        result["exit"] = exit_code
        return result
    last_line = last_nonempty_line(log_text or "")
    if not last_line and exit_code is None:
        result = check(False, None, latency, "auto-update log is empty")
        result["last_line"] = ""
        result["exit"] = None
        return result
    failed = (exit_code is not None and exit_code != 0) or looks_like_failure(last_line)
    result = check(not failed, exit_code, latency, None)
    result["last_line"] = last_line
    result["exit"] = exit_code
    if failed and exit_code not in (None, 0):
        result["error"] = f"darwin-auto-update exit {exit_code}"
    elif failed:
        result["error"] = "darwin-auto-update log ends with an error"
    return result


def prune_history(history_dir: Path, today: date, retention_days: int) -> None:
    """Keep the last retention_days daily files, including today."""
    if retention_days < 1:
        raise ValueError("retention_days must be >= 1")
    cutoff = today - timedelta(days=retention_days)
    if not history_dir.is_dir():
        return
    for path in history_dir.glob("*.jsonl"):
        try:
            file_day = date.fromisoformat(path.stem)
        except ValueError:
            continue
        if file_day <= cutoff:
            path.unlink()


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def append_history(history_dir: Path, today: date, payload: dict) -> None:
    history_dir.mkdir(parents=True, exist_ok=True)
    path = history_dir / f"{today.isoformat()}.jsonl"
    line = json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(line)
    os.chmod(path, 0o600)


def collect(http_results: dict[str, dict], local: dict[str, dict], timestamp: str) -> dict:
    checks = dict(http_results)
    checks["spark_vllm"] = classify_vllm(checks["spark_vllm"], checks["spark_ollama"])
    checks.update(local)
    return {
        "timestamp": timestamp,
        "host": "radon",
        "latency_unit": "ms",
        "checks": checks,
    }


def publish(payload: dict, state_dir: Path, today: date, retention_days: int) -> Path:
    state_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(state_dir, 0o700)
    latest = state_dir / "latest.json"
    atomic_write(latest, json.dumps(payload, indent=2, sort_keys=True) + "\n")
    history = state_dir / "history"
    append_history(history, today, payload)
    prune_history(history, today, retention_days)
    return latest


class RealProbes:
    def __init__(self, curl_bin: str, agent_volume: str, auto_update_log: Path):
        self.curl_bin = curl_bin
        self.agent_volume = agent_volume
        self.auto_update_log = auto_update_log

    def http(self, spec: dict) -> dict:
        started = time.monotonic()
        env = {
            "PATH": "/usr/bin:/bin",
            "HOME": "/var/empty",
        }
        try:
            completed = subprocess.run(
                curl_argv(self.curl_bin, spec["url"]),
                capture_output=True,
                text=True,
                timeout=8,
                env=env,
                check=False,
            )
            latency = int((time.monotonic() - started) * 1000)
            result = interpret_http(
                spec["kind"],
                completed.returncode,
                completed.stdout,
                completed.stderr,
                latency,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            latency = int((time.monotonic() - started) * 1000)
            result = check(False, None, latency, str(exc)[:300])
        result["target"] = spec["url"]
        return result

    def locals(self) -> dict[str, dict]:
        return {
            "agent_volume": self._agent_volume(),
            "auto_update": self._auto_update(),
            "disk": self._disk(),
        }

    def _timed(self, function):
        started = time.monotonic()
        value = function()
        return value, int((time.monotonic() - started) * 1000)

    def _agent_volume(self) -> dict:
        def read_mount() -> str:
            completed = subprocess.run(
                ["/sbin/mount"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if completed.returncode != 0:
                raise OSError(completed.stderr.strip() or "mount failed")
            return completed.stdout

        try:
            text, latency = self._timed(read_mount)
            result = agent_volume_check(text, self.agent_volume, latency)
        except (OSError, subprocess.TimeoutExpired) as exc:
            result = check(False, None, 0, str(exc)[:300])
        result["target"] = self.agent_volume
        return result

    def _disk(self) -> dict:
        def read_df() -> str:
            completed = subprocess.run(
                ["/bin/df", "-kP", "/"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if completed.returncode != 0:
                raise OSError(completed.stderr.strip() or "df failed")
            return completed.stdout

        try:
            text, latency = self._timed(read_df)
            result = disk_check(text, "/", latency)
        except (OSError, subprocess.TimeoutExpired) as exc:
            result = check(False, None, 0, str(exc)[:300])
        result["target"] = "/"
        return result

    def _auto_update(self) -> dict:
        started = time.monotonic()
        log_text = None
        log_error = None
        try:
            log_text = self.auto_update_log.read_text(encoding="utf-8", errors="replace")
        except FileNotFoundError:
            log_error = "log missing"
        except PermissionError:
            log_error = "log not readable"
        except OSError as exc:
            log_error = str(exc)[:300]
        launchctl_text = None
        try:
            completed = subprocess.run(
                ["/bin/launchctl", "print", "system/org.nixos.darwin-auto-update"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            launchctl_text = f"{completed.stdout}\n{completed.stderr}"
        except (OSError, subprocess.TimeoutExpired):
            launchctl_text = None
        latency = int((time.monotonic() - started) * 1000)
        result = auto_update_check(log_text, log_error, launchctl_text, latency)
        result["target"] = str(self.auto_update_log)
        return result


def exclusive_lock(state_dir: Path):
    """Hold the state directory so two launchd starts cannot tear latest.json."""
    state_dir.mkdir(parents=True, exist_ok=True)
    handle = (state_dir / ".lock").open("a", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return None
    os.chmod(handle.name, 0o600)
    return handle


def run_probe(probes: RealProbes, state_dir: Path, retention_days: int, timestamp: str, today: date) -> Path:
    with ThreadPoolExecutor(max_workers=len(HTTP_CHECKS)) as pool:
        futures = {spec["name"]: pool.submit(probes.http, spec) for spec in HTTP_CHECKS}
        http_results = {name: future.result() for name, future in futures.items()}
    payload = collect(http_results, probes.locals(), timestamp)
    return publish(payload, state_dir, today, retention_days)


def gate_user(actual: str, required: str) -> int | None:
    """1 refuses root and hermes. 0 skips any other unexpected account. None proceeds."""
    if actual in FORBIDDEN_USERS:
        print(f"radon-fleet-health: refusing to run as {actual}", file=sys.stderr)
        return 1
    if actual != required:
        print(f"radon-fleet-health: skipping, running as {actual}, expected {required}", file=sys.stderr)
        return 0
    return None


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read-only radon fleet health probe")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--retention-days", type=int, default=14)
    parser.add_argument("--auto-update-log", default="/var/log/darwin-auto-update.log")
    parser.add_argument("--agent-volume", default="/Volumes/Agent")
    parser.add_argument("--curl", default="/usr/bin/curl")
    parser.add_argument("--require-user", default="joost")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    gated = gate_user(_current_user(), args.require_user)
    if gated is not None:
        return gated
    if args.retention_days < 1:
        print("retention-days must be >= 1", file=sys.stderr)
        return 1
    state_dir = Path(args.state_dir)
    lock = exclusive_lock(state_dir)
    if lock is None:
        print("radon-fleet-health: already running", file=sys.stderr)
        return 0
    try:
        now = datetime.now(timezone.utc)
        probes = RealProbes(args.curl, args.agent_volume, Path(args.auto_update_log))
        run_probe(
            probes,
            state_dir,
            args.retention_days,
            now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            now.date(),
        )
    finally:
        lock.close()
    return 0


def _current_user() -> str:
    import getpass

    return getpass.getuser()


if __name__ == "__main__":
    sys.exit(main())
