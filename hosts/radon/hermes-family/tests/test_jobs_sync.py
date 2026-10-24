import argparse
import fcntl
import io
import json
import os
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from hermes_family import jobs_sync
from tests.support import temp_dir

PERSONAL = "telegram:123456789"


class FakeHermes:
    """The `hermes cron` subcommands jobs-sync uses, applied to jobs.json the
    way cron/jobs.py stores them (create_job, cron/jobs.py:1868-1905)."""

    def __init__(self, home: Path):
        self.home = home
        self.argvs: list[list[str]] = []
        self.next_id = 0

    def jobs(self) -> list[dict]:
        return jobs_sync.load_jobs(self.home)

    def save(self, jobs: list[dict]) -> None:
        path = jobs_sync.jobs_file(self.home)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"jobs": jobs, "updated_at": "2026-10-24T12:00:00+02:00"}))

    def __call__(self, argv: list[str]) -> None:
        self.argvs.append(argv)
        parser = argparse.ArgumentParser()
        sub = parser.add_subparsers(dest="command")
        create = sub.add_parser("create")
        create.add_argument("schedule")
        create.add_argument("prompt", nargs="?")
        edit = sub.add_parser("edit")
        edit.add_argument("job_id")
        edit.add_argument("--schedule")
        edit.add_argument("--prompt")
        resume = sub.add_parser("resume")
        resume.add_argument("job_id")
        for p in (create, edit):
            for flag in ("--name", "--deliver", "--script", "--model", "--provider", "--paused-reason"):
                p.add_argument(flag)
            p.add_argument("--no-agent", dest="no_agent", action="store_const", const=True)
        create.add_argument("--paused", action="store_true")
        edit.add_argument("--agent", dest="no_agent", action="store_const", const=False)
        assert argv[0] == "cron"
        args = parser.parse_args(argv[1:])
        jobs = self.jobs()
        if args.command == "create":
            assert (self.home / "scripts" / args.script).is_file() if args.script else True, "script must exist"
            self.next_id += 1
            jobs.append({
                "id": f"job{self.next_id:09d}", "name": args.name, "prompt": args.prompt or "",
                "schedule": {"kind": "cron", "expr": args.schedule, "display": args.schedule},
                "script": args.script, "no_agent": bool(args.no_agent), "deliver": args.deliver,
                "model": args.model, "provider": args.provider, "enabled_toolsets": None,
                "enabled": not args.paused, "state": "paused" if args.paused else "scheduled",
            })
        else:
            (job,) = [j for j in jobs if j["id"] == args.job_id]
            if args.command == "resume":
                job.update(enabled=True, state="scheduled")
            else:
                if args.schedule:
                    job["schedule"] = {"kind": "cron", "expr": args.schedule, "display": args.schedule}
                for field in ("prompt", "deliver", "script", "model", "provider"):
                    value = getattr(args, field)
                    if value is not None:
                        job[field] = value or None if field != "prompt" else value
                if args.no_agent is not None:
                    job["no_agent"] = args.no_agent
        self.save(jobs)


class JobsSyncTest(unittest.TestCase):
    def setUp(self):
        self.home = temp_dir(self) / ".hermes"
        self.home.mkdir()
        self.jobs_dir = Path("/Volumes/Agent/hermes/jobs")
        self.hermes = FakeHermes(self.home)
        self.specs = tuple(jobs_sync.resolve(spec, PERSONAL) for spec in jobs_sync.JOBS)

    def sync(self, dry_run: bool = False) -> list[str]:
        jobs_sync.write_wrappers(self.home, self.jobs_dir, self.specs)
        return jobs_sync.sync(self.home, self.specs, self.hermes, dry_run=dry_run)

    def by_name(self) -> dict[str, dict]:
        return {job["name"]: job for job in self.hermes.jobs()}

    def test_creates_the_six_jobs_exactly_as_the_plan_says(self):
        report = self.sync()
        self.assertEqual(report, [f"{spec.name}: create" for spec in jobs_sync.JOBS])
        jobs = self.by_name()
        table = {name: (job["schedule"]["expr"], job["script"], job["no_agent"], job["deliver"], job["model"],
                        job["provider"], job["enabled_toolsets"], job["enabled"])
                 for name, job in jobs.items()}
        self.assertEqual(table, {
            "family-pickup": ("0 14 * * 1-5", "pickup.sh", True, "telegram", None, None, None, True),
            "family-mail-parsing": ("*/15 7-21 * * *", "mail-fetch.sh", False, "local", "spark/dsv41",
                                    "aperture-local", ["gcal-proposals"], True),
            "family-mail-notifier": ("5-59/15 7-21 * * *", "notifier.sh", True, "telegram", None, None, None, True),
            "family-plan-ahead": ("0 16 * * 5", "plan-ahead-weather.sh", False, "telegram", None, None,
                                  ["web", "gcal-read"], True),
            "family-evening-brief": ("0 20 * * *", None, False, PERSONAL, None, None, ["gcal-read"], True),
            "agent-tooling-digest": ("0 9 * * 6", None, False, PERSONAL, None, None,
                                     ["web", "skills", "todo", "no_mcp"], True),
        })

    def test_new_jobs_are_created_paused_and_resumed_after_their_toolsets_are_set(self):
        self.sync()
        create = next(argv for argv in self.hermes.argvs if "family-mail-parsing" in argv)
        self.assertIn("--paused", create)
        job_id = self.by_name()["family-mail-parsing"]["id"]
        self.assertIn(["cron", "resume", job_id], self.hermes.argvs)

    def test_second_run_changes_nothing(self):
        self.sync()
        calls = len(self.hermes.argvs)
        self.assertEqual(self.sync(), [f"{spec.name}: unchanged" for spec in jobs_sync.JOBS])
        self.assertEqual(len(self.hermes.argvs), calls)
        self.assertEqual(len(self.hermes.jobs()), 6)
        self.assertEqual(jobs_sync.verify(self.home, self.specs), [])

    def test_drift_is_edited_back_in_place(self):
        self.sync()
        jobs = self.hermes.jobs()
        for job in jobs:
            if job["name"] == "family-mail-parsing":
                job.update(model=None, provider=None, deliver="telegram", enabled_toolsets=["web", "gcal-proposals"])
                parse_id = job["id"]
            if job["name"] == "family-pickup":
                job["schedule"] = {"kind": "cron", "expr": "0 15 * * 1-5"}
        self.hermes.save(jobs)
        report = self.sync()
        self.assertIn("family-mail-parsing: update deliver, model, provider, enabled_toolsets", report)
        self.assertIn("family-pickup: update schedule", report)
        self.assertIn(["cron", "edit", parse_id, "--deliver", "local", "--model", "spark/dsv41",
                       "--provider", "aperture-local"], self.hermes.argvs)
        self.assertEqual(jobs_sync.verify(self.home, self.specs), [])
        self.assertEqual(len(self.hermes.jobs()), 6)

    def test_an_unwanted_model_pin_is_cleared(self):
        self.sync()
        jobs = self.hermes.jobs()
        for job in jobs:
            if job["name"] == "family-evening-brief":
                job.update(model="claude-sonnet-5-5", provider="aperture-claude")
                brief_id = job["id"]
        self.hermes.save(jobs)
        self.sync()
        self.assertIn(["cron", "edit", brief_id, "--model", "", "--provider", ""], self.hermes.argvs)

    def test_duplicate_names_stop_the_run_before_any_change(self):
        self.hermes.save([{"id": "a", "name": "family-pickup"}, {"id": "b", "name": "family-pickup"}])
        with self.assertRaises(RuntimeError):
            self.sync()
        self.assertEqual(self.hermes.argvs, [])

    def test_dry_run_changes_nothing(self):
        report = self.sync(dry_run=True)
        self.assertEqual(report, [f"{spec.name}: create" for spec in jobs_sync.JOBS])
        self.assertEqual(self.hermes.argvs, [])

    def test_wrappers_are_real_files_in_the_scripts_dir_that_exec_the_job_links(self):
        self.sync()
        wrapper = self.home / "scripts" / "mail-fetch.sh"
        self.assertFalse(wrapper.is_symlink())
        self.assertEqual(wrapper.read_text(), "#!/bin/bash\nexec /Volumes/Agent/hermes/jobs/mail-fetch \"$@\"\n")
        self.assertEqual(sorted(p.name for p in (self.home / "scripts").iterdir()),
                         ["mail-fetch.sh", "notifier.sh", "pickup.sh", "plan-ahead-weather.sh"])

    def test_toolsets_write_waits_for_the_store_lock_and_keeps_other_fields(self):
        self.hermes.save([{"id": "x1", "name": "other", "enabled_toolsets": None, "custom": 1}])
        lock_path = self.home / "cron" / ".jobs.lock"
        with open(lock_path, "a+") as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            with mock.patch.object(jobs_sync, "LOCK_TIMEOUT_S", 0.3), self.assertRaises(TimeoutError):
                jobs_sync.set_enabled_toolsets(self.home, "x1", ["web"])
        jobs_sync.set_enabled_toolsets(self.home, "x1", ["web"])
        (job,) = self.hermes.jobs()
        self.assertEqual((job["enabled_toolsets"], job["custom"]), (["web"], 1))
        self.assertEqual(os.stat(jobs_sync.jobs_file(self.home)).st_mode & 0o777, 0o600)


class MainTest(unittest.TestCase):
    def test_personal_deliver_must_not_be_the_family_group(self):
        for target in ("telegram", "local", "origin"):
            with mock.patch.dict(os.environ, {"HERMES_HOME": "/tmp/x"}), \
                    redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                jobs_sync.main(["--jobs-dir", "/j", "--personal-deliver", target])

    def test_dry_run_prints_the_plan(self):
        home = temp_dir(self)
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"HERMES_HOME": str(home)}), redirect_stdout(out):
            self.assertEqual(jobs_sync.main(["--jobs-dir", "/j", "--personal-deliver", PERSONAL, "--dry-run"]), 0)
        self.assertIn("family-mail-parsing: create", out.getvalue())
        self.assertFalse((home / "scripts").exists())


if __name__ == "__main__":
    unittest.main()
