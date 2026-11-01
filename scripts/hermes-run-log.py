#!/usr/bin/env python3
"""Append one JSON line per finished Hermes cron run to runs.jsonl.

Hermes shell hooks cannot carry this record: no hook fires for a cron run as
such, `--no-agent` script jobs start no agent, and `on_session_end` has no
tokens, cost, provider or duration (agent/turn_finalizer.py:796-807 at
hermes-agent 81a55437). So this collector reads the stores Hermes already
writes, read-only:

- `cron/executions.db`, table `executions`: one row per attempt with its
  terminal status, start and finish times and error (cron/executions.py:56-97).
  Every job kind gets a row, agent or not.
- `state.db`: the scheduler admits an agent run under request id
  `cron:<job_id>:<execution_id>` from principal `cron-owner`, and the
  admission's `target_session_id` is the run's session
  (hermes_state_keys.py:11-22, gateway/session_cron.py:53-61 and 79-81). That
  session and its child sessions (compression, subagents) hold the model,
  token counts and cost (hermes_state_common.py:461-529, 591-607).

A row names its job and route from `cron/jobs.json`. A job's record can be
edited or gone before its run is logged, so the collector keeps every version
of every job it has seen in `runs-jobs.json` next to the log and gives a run
the version in force when it was claimed; a run of a job it never saw is logged
under the job's id, without a route.

Run it as the Hermes user. It is idempotent: each row carries its
`execution_id`, and a run appends only executions whose id runs.jsonl does not
hold yet. The log is its own checkpoint, so a crash at any point cannot log an
execution twice; a row cut off mid-write is not counted and is written again.
"""

from __future__ import annotations

import argparse
import dataclasses
import fcntl
import json
import os
import re
import sqlite3
import sys
from contextlib import closing, nullcontext
from datetime import UTC, datetime
from pathlib import Path
from typing import Optional

TERMINAL_STATUSES = ("completed", "failed", "unknown")
CRON_PRINCIPAL_ID = "cron-owner"
MAX_ERROR_CHARS = 500
# cron/scheduler_bookkeeping.py at 81a55437 sets this only after an otherwise
# successful run returns a blank final response. This is an observable empty
# answer, not proof of the raw HTTP status or of a server-side parser fault.
EMPTY_RESPONSE_ERROR = "Agent completed but produced empty response (model error, timeout, or misconfiguration)"

# Hermes records an agent run's failure as "<exception type>: <message>"
# (cron/scheduler.py:2652-2653 at hermes-agent 81a55437). A model call that
# keeps failing ends the turn with a summary of its last error
# (agent/turn_recovery.py:1145-1240, agent/api_error_summary.py:155-226), and
# cron raises that summary as a RuntimeError (cron/scheduler.py:2086-2087); a
# model-client exception can also escape with its own type. Only those shapes
# count, so the inactivity watchdog's TimeoutError, a script timeout or an
# agent's own [CRON_FAILURE] report of a failing calendar service is not blamed
# on the model host. Of the statuses, an overloaded or rate-limiting host
# counts; a 4xx such as an unknown model is a configuration fault.
_EXCEPTION_PREFIX = re.compile(r"(?:[\w.]+\.)?([A-Z]\w*(?:Error|Timeout|Exception))\s*:\s*(.*)", re.DOTALL)
# The openai and anthropic SDKs' connection and timeout errors and the httpx
# transport errors beneath them.
_MODEL_CLIENT_TRANSPORT_ERRORS = frozenset({
    "APIConnectionError", "APITimeoutError", "ConnectError", "ConnectTimeout", "ReadTimeout", "WriteTimeout",
    "PoolTimeout", "ReadError", "WriteError", "RemoteProtocolError",
})
# An SDK status error reads "Error code: 503 - {...}", Hermes's summary of one
# "HTTP 503: ..." (agent/api_error_summary.py:71-73). 529 is Anthropic's
# "overloaded", for the Claude route.
_MODEL_HOST_STATUS = re.compile(r"(?:Error code:|HTTP) (?:429|50[0-4]|529)\b")
# Hermes's summaries of an SDK connection error, an SDK timeout and a DNS
# failure (agent/api_error_summary.py:161-171, 226).
_UNREACHABLE_SUMMARIES = ("Connection error.", "Request timed out.", "Hermes can't reach the model provider.")


@dataclasses.dataclass(frozen=True)
class Execution:
    id: str
    job_id: str
    status: str
    claimed_at: str
    started_at: Optional[str]
    finished_at: Optional[str]
    error: Optional[str]


@dataclasses.dataclass(frozen=True)
class Job:
    name: str
    no_agent: bool
    model: Optional[str]
    provider: Optional[str]


@dataclasses.dataclass(frozen=True)
class Usage:
    model: Optional[str]
    input_tokens: int
    output_tokens: int
    cost: Optional[float]


@dataclasses.dataclass(frozen=True)
class Route:
    """The cron default route, from config.yaml's cron.model and cron.model_provider."""

    model: Optional[str]
    provider: Optional[str]


def _parse_time(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    parsed = datetime.fromisoformat(value)
    return parsed if parsed.tzinfo else parsed.astimezone()


def _utc_iso(moment: datetime) -> str:
    return moment.astimezone(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def _clean_error(error: Optional[str]) -> Optional[str]:
    if not error:
        return None
    return re.sub(r"\s+", " ", error).strip()[:MAX_ERROR_CHARS]


def is_model_host_failure(error: Optional[str]) -> bool:
    """Whether an agent run's recorded error is the model client's, for an unreachable or overloaded host."""
    match = _EXCEPTION_PREFIX.match(error or "")
    if match is None:
        return False
    error_type, message = match.groups()
    return (
        error_type in _MODEL_CLIENT_TRANSPORT_ERRORS
        or _MODEL_HOST_STATUS.match(message) is not None
        or message.startswith(_UNREACHABLE_SUMMARIES)
    )


def build_row(execution: Execution, job: Optional[Job], usage: Optional[Usage], route: Route) -> dict:
    """The runs.jsonl row for one finished execution, keys in the documented order."""
    finished = _parse_time(execution.finished_at) or _parse_time(execution.claimed_at)
    started = _parse_time(execution.started_at)
    if job is not None:
        agent_run = not job.no_agent
        model = ((usage.model if usage else None) or job.model or route.model) if agent_run else None
        provider = (job.provider or route.provider) if agent_run else None
    else:
        # A job neither jobs.json nor the cache knows: only a session shows it
        # ran an agent, and nothing shows the job's own route.
        agent_run = usage is not None
        model = usage.model if usage else None
        provider = None
    failed = execution.status != "completed"
    return {
        "ts": _utc_iso(finished),
        "job": job.name if job else execution.job_id,
        "model": model,
        "provider": provider,
        "input_tokens": usage.input_tokens if usage else None,
        "output_tokens": usage.output_tokens if usage else None,
        "cost": usage.cost if usage else None,
        "duration_s": round((finished - started).total_seconds(), 3) if started else None,
        "status": execution.status,
        "model_host_failure": agent_run and failed and is_model_host_failure(execution.error),
        "empty_response": agent_run and execution.status == "failed" and execution.error == EMPTY_RESPONSE_ERROR,
        "error": _clean_error(execution.error) if failed else None,
        "execution_id": execution.id,
    }


def _connect_read_only(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def terminal_executions(conn: sqlite3.Connection) -> list[Execution]:
    placeholders = ",".join("?" * len(TERMINAL_STATUSES))
    rows = conn.execute(
        f"SELECT id, job_id, status, claimed_at, started_at, finished_at, error FROM executions"
        f" WHERE status IN ({placeholders}) ORDER BY COALESCE(finished_at, claimed_at), id",
        TERMINAL_STATUSES,
    )
    return [Execution(**dict(row)) for row in rows]


def session_usage(conn: sqlite3.Connection, job_id: str, execution_id: str) -> Optional[Usage]:
    admission = conn.execute(
        "SELECT target_session_id FROM session_admissions"
        " WHERE principal_id = ? AND request_id = ? ORDER BY seq LIMIT 1",
        (CRON_PRINCIPAL_ID, f"cron:{job_id}:{execution_id}"),
    ).fetchone()
    if admission is None:
        return None
    root = admission["target_session_id"]
    totals = conn.execute(
        """WITH RECURSIVE run(id) AS (
               SELECT ? UNION SELECT s.id FROM sessions s JOIN run ON s.parent_session_id = run.id)
           SELECT COUNT(*) AS sessions,
                  COALESCE(SUM(input_tokens), 0) AS input_tokens,
                  COALESCE(SUM(output_tokens), 0) AS output_tokens,
                  SUM(COALESCE(actual_cost_usd, estimated_cost_usd)) AS cost
           FROM sessions WHERE id IN (SELECT id FROM run)""",
        (root,),
    ).fetchone()
    if not totals["sessions"]:
        return None
    model = conn.execute("SELECT model FROM sessions WHERE id = ?", (root,)).fetchone()["model"]
    return Usage(model, totals["input_tokens"], totals["output_tokens"], totals["cost"])


def load_jobs(path: Path) -> dict[str, Job]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"), strict=False)
    except FileNotFoundError:
        return {}
    jobs = data.get("jobs", []) if isinstance(data, dict) else []
    return {
        str(job["id"]): Job(
            name=str(job.get("name") or job["id"]),
            no_agent=bool(job.get("no_agent")),
            model=job.get("model") or None,
            provider=job.get("provider") or None,
        )
        for job in jobs
        if isinstance(job, dict) and job.get("id")
    }


# Each job's metadata versions, oldest first, with the time a pass first saw each.
JobHistory = dict[str, list[tuple[datetime, Job]]]


def job_cache_path(run_log: Path) -> Path:
    """The collector's record of every job version it has seen, next to runs.jsonl."""
    return run_log.with_name(f"{run_log.stem}-jobs.json")


def load_job_cache(path: Path) -> JobHistory:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        return {}  # rebuilt from jobs.json below; only removed jobs and old versions are lost
    history = {}
    for job_id, versions in data.items() if isinstance(data, dict) else ():
        try:
            history[job_id] = [
                (datetime.fromisoformat(fields.pop("seen_at")), Job(**fields)) for fields in versions
            ]
        except (AttributeError, KeyError, TypeError, ValueError):
            continue
    return history


def save_job_cache(path: Path, history: JobHistory) -> None:
    data = {
        job_id: [{"seen_at": seen.isoformat(), **dataclasses.asdict(job)} for seen, job in history[job_id]]
        for job_id in sorted(history)
    }
    staged = path.with_name(f"{path.name}.tmp")
    with staged.open("w", encoding="utf-8") as handle:
        handle.write(json.dumps(data, indent=1))
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(staged, path)
    # The rename itself must reach the disk too, or a power cut can bring back
    # the old cache, or none.
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def record_jobs(history: JobHistory, jobs: dict[str, Job], now: datetime) -> bool:
    """Add each job whose metadata differs from its latest version; return whether any did."""
    changed = False
    for job_id, job in jobs.items():
        versions = history.setdefault(job_id, [])
        if not versions or versions[-1][1] != job:
            versions.append((now, job))
            changed = True
    return changed


def job_at(versions: list[tuple[datetime, Job]], moment: datetime) -> Optional[Job]:
    """The version in force at moment: the last one a pass had seen by then, else the first."""
    if not versions:
        return None
    seen = [job for seen_at, job in versions if seen_at <= moment]
    return seen[-1] if seen else versions[0][1]


def logged_execution_ids(lines: list[str]) -> set[str]:
    ids = set()
    for line in lines:
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(row, dict) and isinstance(row.get("execution_id"), str):
            ids.add(row["execution_id"])
    return ids


def collect(hermes_home: Path, run_log: Path, route: Route) -> int:
    """Append the rows for every terminal execution not logged yet; return how many."""
    ledger = hermes_home / "cron" / "executions.db"
    jobs_file = hermes_home / "cron" / "jobs.json"
    if not ledger.exists() and not jobs_file.exists():
        return 0
    run_log.parent.mkdir(parents=True, exist_ok=True)
    with open(run_log, "a+b") as log:
        fcntl.flock(log, fcntl.LOCK_EX)
        log.seek(0)
        data = log.read()
        # A crash mid-append leaves a last line without its newline, maybe
        # ending inside a multibyte character. Drop it as bytes, before
        # decoding: its execution is then not logged, so it is written again
        # below. A line garbled some other way must not stop every later pass.
        if data and not data.endswith(b"\n"):
            data = data[: data.rfind(b"\n") + 1]
            log.truncate(len(data))
        logged = logged_execution_ids(data.decode("utf-8", errors="replace").splitlines())

        # A job's runs outlive its record in jobs.json: `hermes cron remove`
        # drops it at once, the retention sweep drops a finished one-shot or
        # repeat-limited job after cron.completed_retention_days, 7 by default,
        # and the dispatch-limit guard drops a one-shot whose tick died
        # (cron/jobs.py:2260-2263, 2399-2402, 2800-2849, 3152-3191). And an
        # edit replaces the record before a pass logs the runs it already
        # made. So every pass records each job's metadata when it changes, and
        # a run gets the version in force when the scheduler claimed it.
        #
        # Neither Hermes store says when a job was edited: jobs.json has no
        # per-job edit time (its top-level updated_at moves on every write,
        # run bookkeeping included), and the execution ledger keeps no copy of
        # the job. So a version counts from the pass that first saw it. A run
        # claimed after an edit but before the next pass, within five minutes,
        # gets the version from before the edit; its model still comes from
        # its session when it has one. A run claimed before the first pass
        # that saw its job gets that first version.
        cache_path = job_cache_path(run_log)
        history = load_job_cache(cache_path)
        if record_jobs(history, load_jobs(jobs_file), datetime.now(UTC)):
            save_job_cache(cache_path, history)

        if not ledger.exists():
            return 0
        with closing(_connect_read_only(ledger)) as conn:
            new = [e for e in terminal_executions(conn) if e.id not in logged]
        if not new:
            return 0
        state_db = hermes_home / "state.db"
        with closing(_connect_read_only(state_db)) if state_db.exists() else nullcontext() as state:
            rows = [
                build_row(e, job_at(history.get(e.job_id, []), _parse_time(e.claimed_at)),
                          session_usage(state, e.job_id, e.id) if state else None, route)
                for e in new
            ]
        log.write("".join(json.dumps(row) + "\n" for row in rows).encode())
        log.flush()
        os.fsync(log.fileno())
    return len(rows)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--hermes-home", type=Path, required=True, help="HERMES_HOME")
    parser.add_argument("--run-log", type=Path, required=True, help="runs.jsonl to append to")
    parser.add_argument("--cron-model", help="config.yaml cron.model, for runs with no session")
    parser.add_argument("--cron-provider", help="config.yaml cron.model_provider")
    args = parser.parse_args(argv)
    count = collect(args.hermes_home, args.run_log, Route(args.cron_model, args.cron_provider))
    if count:
        print(f"hermes-run-log: appended {count} row(s) to {args.run_log}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
