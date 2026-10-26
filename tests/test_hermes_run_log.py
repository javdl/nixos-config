"""Run-log collector against stores shaped like Hermes 81a55437 writes them.

The schema comes from tests/fixtures/hermes-81a5543-cron-stores.sql, generated
from the pinned Hermes source. Rows follow the writers: create_execution,
mark_execution_running and finish_execution (cron/executions.py:213-340),
create_job (cron/jobs.py:1868-1905), the cron admission (gateway/session_cron.py:79-81)
and SessionDB usage totals. RealHermesStoreTests repeats the main case with
Hermes's own writers when this runs under a Hermes Python.
"""

import importlib.util
import json
import os
import sqlite3
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCHEMA = (REPO / "tests" / "fixtures" / "hermes-81a5543-cron-stores.sql").read_text()


def load_collector():
    spec = importlib.util.spec_from_file_location("hermes_run_log", REPO / "scripts" / "hermes-run-log.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


run_log = load_collector()
ROUTE = run_log.Route("spark/dsv41", "aperture-local")


def job_record(job_id, name, *, no_agent=False, model=None, provider=None):
    return {
        "id": job_id, "name": name, "prompt": "" if no_agent else "Reply with OK", "skills": [], "skill": None,
        "model": model, "provider": provider, "base_url": None,
        "script": "pickup.sh" if no_agent else None, "no_agent": no_agent,
        "schedule": {"kind": "cron", "expr": "0 14 * * 1-5", "display": "0 14 * * 1-5"},
        "enabled": True, "state": "scheduled", "last_status": None, "last_error": None,
    }


class Stores:
    def __init__(self, root: Path):
        self.home = root / ".hermes"
        (self.home / "cron").mkdir(parents=True)
        self.ledger = sqlite3.connect(self.home / "cron" / "executions.db")
        self.state = sqlite3.connect(self.home / "state.db")
        for conn in (self.ledger, self.state):
            conn.executescript(SCHEMA)
        self.run_log = root / "runs.jsonl"
        self.jobs = []

    def close(self):
        self.ledger.close()
        self.state.close()

    def add_job(self, record):
        self.jobs.append(record)
        (self.home / "cron" / "jobs.json").write_text(
            json.dumps({"jobs": self.jobs, "updated_at": "2026-10-24T14:00:00.000000+02:00"}, indent=2))

    def add_execution(self, job_id, *, status, started, finished, error=None):
        execution_id = uuid.uuid4().hex
        self.ledger.execute(
            "INSERT INTO executions (id, job_id, source, process_id, pid, process_started_at,"
            " status, claimed_at, scheduled_instant) VALUES (?, ?, 'direct', ?, 4242, 1782900000, 'claimed', ?, ?)",
            (execution_id, job_id, uuid.uuid4().hex, started, started))
        self.ledger.execute(
            "UPDATE executions SET status='running', started_at=?, handoff_pending=0,"
            " handoff_started_at=NULL WHERE id=?", (started, execution_id))
        self.ledger.execute(
            "UPDATE executions SET status=?, finished_at=?, error=?, handoff_pending=0,"
            " handoff_started_at=NULL, delivery_outcome=NULL WHERE id=?",
            (status, finished, error, execution_id))
        self.ledger.commit()
        return execution_id

    def add_session(self, session_id, *, model, input_tokens, output_tokens, cost, parent=None):
        self.state.execute(
            "INSERT INTO sessions (id, source, model, parent_session_id, started_at, ended_at, end_reason,"
            " input_tokens, output_tokens, billing_provider, billing_base_url, billing_mode,"
            " estimated_cost_usd, cost_status, cost_source, api_call_count, profile_name)"
            " VALUES (?, 'cron', ?, ?, 1782900000.0, 1782900007.5, 'completed', ?, ?, 'custom',"
            " 'https://ai.buri-hoki.ts.net/v1', 'chat_completions', ?, 'unknown', 'none', 1, 'default')",
            (session_id, model, parent, input_tokens, output_tokens, cost))
        self.state.commit()

    def admit(self, job_id, execution_id, session_id):
        self.state.execute(
            "INSERT INTO session_admissions (admission_id, request_id, principal_id, target_session_id,"
            " lineage_json, payload_json, payload_digest, intent, status, outcome, owner_epoch, generation)"
            " VALUES (?, ?, 'cron-owner', ?, '{}', '{\"text\": \"\"}', ?, 'queue', 'terminal', 'completed', 1, 1)",
            (uuid.uuid4().hex, f"cron:{job_id}:{execution_id}", session_id, uuid.uuid4().hex))
        self.state.commit()

    def collect(self):
        return run_log.collect(self.home, self.run_log, ROUTE)

    def rows(self):
        if not self.run_log.exists():
            return []
        return [json.loads(line) for line in self.run_log.read_text().splitlines()]


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.stores = Stores(Path(self.tmp.name))
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.stores.close)

    def test_agent_run_row_carries_route_tokens_cost_and_duration(self):
        s = self.stores
        s.add_job(job_record("a1b2c3d4e5f6", "Reply with OK"))
        execution = s.add_execution("a1b2c3d4e5f6", status="completed",
                                    started="2026-10-24T14:00:00.250000+02:00",
                                    finished="2026-10-24T14:00:07.750000+02:00")
        s.add_session("local-root", model="spark/dsv41", input_tokens=1200, output_tokens=40, cost=0.0)
        s.add_session("local-child", model="spark/dsv41", input_tokens=300, output_tokens=2, cost=0.0,
                      parent="local-root")
        s.admit("a1b2c3d4e5f6", execution, "local-root")

        self.assertEqual(s.collect(), 1)
        [row] = s.rows()
        self.assertEqual(list(row), ["ts", "job", "model", "provider", "input_tokens", "output_tokens", "cost",
                                     "duration_s", "status", "model_host_failure", "error", "execution_id"])
        self.assertEqual(row, {
            "ts": "2026-10-24T12:00:07Z", "job": "Reply with OK", "model": "spark/dsv41",
            "provider": "aperture-local", "input_tokens": 1500, "output_tokens": 42, "cost": 0.0,
            "duration_s": 7.5, "status": "completed", "model_host_failure": False, "error": None,
            "execution_id": execution,
        })

    def test_unserved_model_is_a_failed_row_but_not_a_model_host_failure(self):
        s = self.stores
        s.add_job(job_record("bad000000001", "OK on a bad model", model="no/such-model", provider="aperture-local"))
        error = ("RuntimeError: Error code: 404 - {'error': {'message': 'model no/such-model not found', "
                 "'type': 'invalid_request_error'}}")
        execution = s.add_execution("bad000000001", status="failed", error=error,
                                    started="2026-10-24T14:05:00+02:00", finished="2026-10-24T14:05:01.5+02:00")
        s.add_session("local-bad", model="no/such-model", input_tokens=0, output_tokens=0, cost=None)
        s.admit("bad000000001", execution, "local-bad")

        s.collect()
        [row] = s.rows()
        self.assertEqual(row["status"], "failed")
        self.assertEqual((row["model"], row["provider"]), ("no/such-model", "aperture-local"))
        self.assertIn("404", row["error"])
        self.assertIs(row["model_host_failure"], False)

    def test_unreachable_model_host_is_flagged(self):
        s = self.stores
        s.add_job(job_record("conn00000001", "mail parsing"))
        s.add_execution("conn00000001", status="failed", error="APIConnectionError: Connection error.",
                        started="2026-10-24T14:15:00+02:00", finished="2026-10-24T14:16:00+02:00")

        s.collect()
        [row] = s.rows()
        self.assertIs(row["model_host_failure"], True)
        self.assertEqual((row["model"], row["provider"]), ("spark/dsv41", "aperture-local"))
        self.assertIsNone(row["input_tokens"])

    def test_a_job_past_its_inactivity_limit_is_not_a_model_host_failure(self):
        s = self.stores
        s.add_job(job_record("idle00000001", "mail parsing"))
        error = ("TimeoutError: Cron job 'mail parsing' idle for 600s (limit 600s)"
                 " — last activity: tool mcp_calendar_create_event")
        s.add_execution("idle00000001", status="failed", error=error,
                        started="2026-10-24T14:15:00+02:00", finished="2026-10-24T14:25:00+02:00")

        s.collect()
        [row] = s.rows()
        self.assertEqual(row["status"], "failed")
        self.assertIs(row["model_host_failure"], False)

    def test_no_agent_run_has_status_and_duration_only(self):
        s = self.stores
        s.add_job(job_record("pick00000001", "pickup", no_agent=True))
        s.add_execution("pick00000001", status="completed",
                        started="2026-10-24T14:00:00+02:00", finished="2026-10-24T14:00:02+02:00")

        s.collect()
        [row] = s.rows()
        self.assertEqual(row["job"], "pickup")
        self.assertEqual((row["status"], row["duration_s"]), ("completed", 2.0))
        for key in ("model", "provider", "input_tokens", "output_tokens", "cost", "error"):
            self.assertIsNone(row[key], key)
        self.assertIs(row["model_host_failure"], False)

    def test_each_execution_is_logged_once(self):
        s = self.stores
        s.add_job(job_record("pick00000001", "pickup", no_agent=True))
        s.add_execution("pick00000001", status="completed",
                        started="2026-10-24T14:00:00+02:00", finished="2026-10-24T14:00:02+02:00")
        self.assertEqual(s.collect(), 1)
        self.assertEqual(s.collect(), 0)
        s.add_execution("pick00000001", status="failed", error="script exited 1",
                        started="2026-10-27T14:00:00+01:00", finished="2026-10-27T14:00:01+01:00")
        self.assertEqual(s.collect(), 1)
        self.assertEqual([r["status"] for r in s.rows()], ["completed", "failed"])

    def test_a_row_cut_off_by_a_crash_is_written_again_once(self):
        s = self.stores
        s.add_job(job_record("pick00000001", "pickup", no_agent=True))
        execution = s.add_execution("pick00000001", status="completed",
                                    started="2026-10-24T14:00:00+02:00", finished="2026-10-24T14:00:02+02:00")
        other = '{"ts": "2026-10-24T11:00:00Z", "job": "family-pickup", "status": "failed"}\n'
        s.run_log.write_text(other + '{"ts": "2026-10-24T12:00:02Z", "job": "pick')
        self.assertEqual(s.collect(), 1)
        self.assertEqual(s.collect(), 0)
        lines = s.run_log.read_text().splitlines()
        self.assertEqual(lines[0] + "\n", other)
        self.assertEqual([json.loads(line).get("execution_id") for line in lines], [None, execution])

    def test_running_attempts_wait_until_they_finish(self):
        s = self.stores
        s.add_job(job_record("pick00000001", "pickup", no_agent=True))
        s.ledger.execute(
            "INSERT INTO executions (id, job_id, source, process_id, pid, status, claimed_at, started_at)"
            " VALUES ('live', 'pick00000001', 'direct', 'p', 1, 'running', '2026-10-24T14:00:00+02:00',"
            " '2026-10-24T14:00:00+02:00')")
        s.ledger.commit()
        self.assertEqual(s.collect(), 0)
        self.assertEqual(s.rows(), [])

    def test_no_ledger_yet_writes_nothing(self):
        home = Path(self.tmp.name) / "fresh"
        self.assertEqual(run_log.collect(home, home / "runs.jsonl", ROUTE), 0)
        self.assertFalse((home / "runs.jsonl").exists())


class ModelHostFailureTests(unittest.TestCase):
    """Error texts in the shapes Hermes 81a55437 records for an agent run."""

    def test_model_client_failures_match(self):
        for error in (
            "APIConnectionError: Connection error.",
            "openai.APITimeoutError: Request timed out.",
            "ReadTimeout: timed out",
            "RuntimeError: Connection error.",
            "RuntimeError: Request timed out.",
            "RuntimeError: Hermes can't reach the model provider. You may be offline. "
            "Check your internet connection and try again.",
            "RuntimeError: HTTP 503: Service Unavailable",
            "RuntimeError: HTTP 429: Too many requests",
            "InternalServerError: Error code: 502 - {'error': {'message': 'Bad gateway'}}",
            "RateLimitError: Error code: 429",
        ):
            with self.subTest(error=error):
                self.assertIs(run_log.is_model_host_failure(error), True)

    def test_other_subsystems_do_not_match(self):
        for error in (
            None,
            "",
            "TimeoutError: Cron job 'mail parsing' idle for 600s (limit 600s) — last activity: tool web_search",
            "TimeoutError: Canonical cron session store acquisition timed out",
            "Script timed out after 120s: pickup.sh",
            "Calendar: HTTP 503 from the proposals service, no event was created.",
            "The calendar service answered 503 Service Unavailable; no event was created.",
            "RuntimeError: MCP server 'calendar' call timed out after 30s",
            "RuntimeError: calendar API returned HTTP 500 for events.insert",
            "RuntimeError: Error code: 404 - {'error': {'message': 'model no/such-model not found'}}",
            "RuntimeError: HTTP 400: reasoning_effort must be one of low, high, xhigh, max",
            "Restart-safe cron worker dispatch failed: connection refused",
        ):
            with self.subTest(error=error):
                self.assertIs(run_log.is_model_host_failure(error), False)


def hermes_importable():
    try:
        import cron.executions  # noqa: F401
        import hermes_state  # noqa: F401
    except ImportError:
        return False
    return True


@unittest.skipUnless(hermes_importable(), "needs a Hermes Python (hermesVenv) on sys.path")
class RealHermesStoreTests(unittest.TestCase):
    def test_rows_from_hermes_own_writers(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / ".hermes"
            home.mkdir()
            os.environ["HERMES_HOME"] = str(home)
            from cron import executions
            from cron.jobs import create_job
            from hermes_state import SessionDB

            job = create_job(prompt="Reply with OK", schedule="every 1h", name="real ok")
            record = executions.create_execution(job["id"], source="direct")
            executions.mark_execution_running(record["id"])
            executions.finish_execution(record["id"], success=True)

            db = SessionDB(home / "state.db")
            db.create_session("local-real", "cron", model="spark/dsv41")
            db.update_token_counts("local-real", input_tokens=900, output_tokens=7, model="spark/dsv41",
                                   estimated_cost_usd=0.0, billing_provider="custom",
                                   billing_base_url="https://ai.buri-hoki.ts.net/v1", api_call_count=1,
                                   source="cron")
            db.close()
            with sqlite3.connect(home / "state.db") as conn:
                conn.execute(
                    "INSERT INTO session_admissions (admission_id, request_id, principal_id, target_session_id,"
                    " lineage_json, payload_json, payload_digest, intent, status, outcome, owner_epoch,"
                    " generation) VALUES ('adm', ?, 'cron-owner', 'local-real', '{}', '{}', 'd', 'queue',"
                    " 'terminal', 'completed', 1, 1)",
                    (f"cron:{job['id']}:{record['id']}",))

            out = Path(tmp) / "runs.jsonl"
            self.assertEqual(run_log.collect(home, out, ROUTE), 1)
            row = json.loads(out.read_text())
            self.assertEqual((row["job"], row["status"], row["model"], row["provider"]),
                             ("real ok", "completed", "spark/dsv41", "aperture-local"))
            self.assertEqual((row["input_tokens"], row["output_tokens"], row["cost"]), (900, 7, 0.0))
            self.assertGreaterEqual(row["duration_s"], 0)


if __name__ == "__main__":
    unittest.main()
