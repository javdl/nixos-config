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

Run it as the Hermes user. It is idempotent: the ids it has logged go to a
seen file, pruned to the ids the ledger still holds.
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

# An unreachable, overloaded or rate-limiting model host. A 4xx such as an
# unknown model is a configuration fault and does not match.
_MODEL_HOST_FAILURE = re.compile(
    r"\b(?:429|50[0-4])\b"
    r"|connection (?:error|refused|reset|aborted)"
    r"|connecterror|apiconnectionerror|apitimeouterror|internalservererror"
    r"|timed out|timeout"
    r"|rate.?limit|overloaded|service unavailable|bad gateway"
    r"|name or service not known|nodename nor servname|no route to host|network is unreachable",
    re.IGNORECASE,
)


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
    return bool(error) and _MODEL_HOST_FAILURE.search(error) is not None


def build_row(execution: Execution, job: Optional[Job], usage: Optional[Usage], route: Route) -> dict:
    """The runs.jsonl row for one finished execution, keys in the documented order."""
    finished = _parse_time(execution.finished_at) or _parse_time(execution.claimed_at)
    started = _parse_time(execution.started_at)
    agent_run = job is None or not job.no_agent
    if agent_run:
        model = (usage.model if usage else None) or (job.model if job else None) or route.model
        provider = (job.provider if job else None) or route.provider
    else:
        model = provider = None
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
        "error": _clean_error(execution.error) if failed else None,
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


def collect(hermes_home: Path, run_log: Path, seen_path: Path, route: Route) -> int:
    """Append the rows for every terminal execution not logged yet; return how many."""
    ledger = hermes_home / "cron" / "executions.db"
    if not ledger.exists():
        return 0
    seen_path.parent.mkdir(parents=True, exist_ok=True)
    with open(seen_path, "a+", encoding="utf-8") as seen_file:
        fcntl.flock(seen_file, fcntl.LOCK_EX)
        seen_file.seek(0)
        seen = set(seen_file.read().split())

        with closing(_connect_read_only(ledger)) as conn:
            executions = terminal_executions(conn)
        new = [e for e in executions if e.id not in seen]

        rows = []
        if new:
            jobs = load_jobs(hermes_home / "cron" / "jobs.json")
            state_db = hermes_home / "state.db"
            with closing(_connect_read_only(state_db)) if state_db.exists() else nullcontext() as state:
                for execution in new:
                    usage = session_usage(state, execution.job_id, execution.id) if state else None
                    rows.append(build_row(execution, jobs.get(execution.job_id), usage, route))
            run_log.parent.mkdir(parents=True, exist_ok=True)
            with open(run_log, "a", encoding="utf-8") as log:
                log.write("".join(json.dumps(row) + "\n" for row in rows))
                log.flush()
                os.fsync(log.fileno())

        seen_file.seek(0)
        seen_file.truncate()
        seen_file.write("".join(e.id + "\n" for e in executions))
        seen_file.flush()
        os.fsync(seen_file.fileno())
    return len(rows)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--hermes-home", type=Path, required=True, help="HERMES_HOME")
    parser.add_argument("--run-log", type=Path, required=True, help="runs.jsonl to append to")
    parser.add_argument("--seen", type=Path, required=True, help="file of execution ids already logged")
    parser.add_argument("--cron-model", help="config.yaml cron.model, for runs with no session")
    parser.add_argument("--cron-provider", help="config.yaml cron.model_provider")
    args = parser.parse_args(argv)
    count = collect(args.hermes_home, args.run_log, args.seen, Route(args.cron_model, args.cron_provider))
    if count:
        print(f"hermes-run-log: appended {count} row(s) to {args.run_log}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
