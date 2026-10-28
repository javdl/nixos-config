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
from tests.support import FAMILY, temp_dir, write_json

PERSONAL = FAMILY["personal_deliver"]


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
                "paused_reason": args.paused_reason if args.paused else None,
            })
        else:
            (job,) = [j for j in jobs if j["id"] == args.job_id]
            if args.command == "resume":
                job.update(enabled=True, state="scheduled", paused_at=None, paused_reason=None)
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
        self.specs = tuple(jobs_sync.resolve(spec, PERSONAL, FAMILY["schedules"]) for spec in jobs_sync.JOBS)

    def sync(self, dry_run: bool = False) -> list[str]:
        jobs_sync.write_wrappers(self.home, self.jobs_dir, self.specs)
        return jobs_sync.sync(self.home, self.specs, self.hermes, dry_run=dry_run)

    def by_name(self) -> dict[str, dict]:
        return {job["name"]: job for job in self.hermes.jobs()}

    def test_creates_the_eight_jobs_exactly_as_the_plan_says(self):
        report = self.sync()
        self.assertEqual(report, [f"{spec.name}: create" for spec in jobs_sync.JOBS])
        jobs = self.by_name()
        self.assertEqual({name: job["schedule"]["expr"] for name, job in jobs.items()}, FAMILY["schedules"])
        table = {name: (job["script"], job["no_agent"], job["deliver"], job["model"],
                        job["provider"], job["enabled_toolsets"], job["enabled"])
                 for name, job in jobs.items()}
        self.assertEqual(table, {
            "family-pickup": ("pickup.sh", True, "telegram", None, None, None, True),
            "family-mail-parsing": ("mail-fetch.sh", False, "local", "spark/dsv41",
                                    "aperture-local", ["gcal-proposals"], True),
            "family-mail-notifier": ("notifier.sh", True, "telegram", None, None, None, True),
            "family-plan-ahead": ("plan-ahead-weather.sh", False, "telegram", None, None,
                                  ["web", "gcal-family"], True),
            "family-evening-brief": (None, False, PERSONAL, None, None, ["gcal-read"], True),
            "agent-tooling-digest": (None, False, PERSONAL, None, None,
                                     ["web", "skills", "todo", "no_mcp"], True),
            "x-bookmarks": ("x-bookmarks.sh", True, PERSONAL, None, None, None, True),
            "x-bookmarks-digest": ("x-bookmarks-digest.sh", False, PERSONAL, None, None, [], True),
        })

    def test_new_jobs_are_created_paused_and_resumed_after_their_toolsets_are_set(self):
        self.sync()
        create = next(argv for argv in self.hermes.argvs if "family-mail-parsing" in argv)
        self.assertIn("--paused", create)
        job_id = self.by_name()["family-mail-parsing"]["id"]
        self.assertIn(["cron", "resume", job_id], self.hermes.argvs)

    def pause(self, name: str, reason: str) -> str:
        jobs = self.hermes.jobs()
        (job,) = [job for job in jobs if job["name"] == name]
        job.update(enabled=False, state="paused", paused_at="2026-10-25T10:00:00+00:00", paused_reason=reason)
        self.hermes.save(jobs)
        return job["id"]

    def test_a_job_left_paused_by_an_interrupted_creation_is_resumed(self):
        self.sync()
        job_id = self.pause("family-plan-ahead", jobs_sync.SYNC_PAUSE_REASON)
        report = self.sync()
        self.assertIn("family-plan-ahead: update resume", report)
        self.assertEqual(self.hermes.argvs[-1], ["cron", "resume", job_id])
        self.assertTrue(self.by_name()["family-plan-ahead"]["enabled"])
        self.assertEqual(jobs_sync.verify(self.home, self.specs), [])

    def test_a_job_paused_by_hand_is_reported_and_left_paused(self):
        self.sync()
        self.pause("family-pickup", "school holiday")
        calls = len(self.hermes.argvs)
        report = self.sync()
        self.assertIn("family-pickup: unchanged (paused by hand; left paused)", report)
        self.assertEqual(len(self.hermes.argvs), calls)
        self.assertFalse(self.by_name()["family-pickup"]["enabled"])
        self.assertEqual(jobs_sync.verify(self.home, self.specs), [])

    def test_second_run_changes_nothing(self):
        self.sync()
        calls = len(self.hermes.argvs)
        self.assertEqual(self.sync(), [f"{spec.name}: unchanged" for spec in jobs_sync.JOBS])
        self.assertEqual(len(self.hermes.argvs), calls)
        self.assertEqual(len(self.hermes.jobs()), 8)
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
        self.assertEqual(len(self.hermes.jobs()), 8)

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
                         ["mail-fetch.sh", "notifier.sh", "pickup.sh", "plan-ahead-weather.sh",
                          "x-bookmarks-digest.sh", "x-bookmarks.sh"])

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
    def setUp(self):
        self.dir = temp_dir(self)

    def main(self, personal_deliver, *flags: str) -> tuple[int, str]:
        return self.run_with(dict(FAMILY, personal_deliver=personal_deliver), *flags)

    def run_with(self, family: dict, *flags: str) -> tuple[int, str]:
        path = write_json(self.dir / "family.json", family)
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"HERMES_HOME": str(self.dir / "home")}), \
                redirect_stdout(out), redirect_stderr(out):
            # A missing binary: a run that gets past validation fails instead of reaching a real hermes.
            code = jobs_sync.main(["--jobs-dir", "/j", "--family", str(path),
                                   "--hermes", str(self.dir / "no-hermes"), *flags])
        return code, out.getvalue()

    def test_personal_deliver_must_name_one_chat(self):
        for target in ("telegram", "local", "origin", "telegram:", "", None):
            code, output = self.main(target)
            self.assertEqual(code, 1, target)
            self.assertIn("personal_deliver must name one chat", output)
        self.assertFalse((self.dir / "home" / "scripts").exists())

    def test_personal_deliver_must_be_a_messaging_platform(self):
        for target in ("local:any", "origin:any", "typo:chat", "webhook:hook", "bot-chat:other",
                       "telegram:123456789,local"):
            code, output = self.main(target)
            self.assertEqual(code, 1, target)
            self.assertIn("personal_deliver must name one chat", output)
            self.assertNotIn(target, output)
        self.assertFalse((self.dir / "home" / "scripts").exists())

    def test_personal_deliver_accepts_one_chat_on_a_messaging_platform(self):
        for target in ("telegram:123456789", "signal:+31600000001", "matrix:!kamer:example.org"):
            code, output = self.main(target, "--dry-run")
            self.assertEqual(code, 0, output)

    def test_schedules_must_be_an_object(self):
        without = {key: value for key, value in FAMILY.items() if key != "schedules"}
        for family in (without, dict(FAMILY, schedules=None), dict(FAMILY, schedules=["30 12 * * 1-5"])):
            code, output = self.run_with(family)
            self.assertEqual(code, 1)
            self.assertIn("the family file needs schedules", output)
        self.assertFalse((self.dir / "home").exists())

    def test_every_job_needs_a_five_field_cron_expression(self):
        cases = [("family-pickup", None), ("family-plan-ahead", "30 17 * * *  4"), ("family-evening-brief", 2130),
                 ("agent-tooling-digest", "@weekly"), ("family-mail-notifier", "10-59/20 8-20 * *"),
                 ("family-mail-parsing", "")]
        for name, value in cases:
            schedules = dict(FAMILY["schedules"])
            if value is None:
                del schedules[name]
            else:
                schedules[name] = value
            code, output = self.run_with(dict(FAMILY, schedules=schedules))
            self.assertEqual(code, 1, name)
            self.assertIn(f"schedules has no five-field cron expression for {name}\n", output)
            if value:
                self.assertNotIn(str(value), output)
        self.assertFalse((self.dir / "home").exists())

    def test_schedules_ignore_other_keys_and_extra_whitespace(self):
        schedules = dict(FAMILY["schedules"], **{"old-job": "x", "family-pickup": " 30  12 * * 1-5 "})
        code, output = self.run_with(dict(FAMILY, schedules=schedules), "--dry-run")
        self.assertEqual(code, 0, output)
        family = write_json(self.dir / "family.json", dict(FAMILY, schedules=schedules))
        self.assertEqual(jobs_sync.schedules(family), FAMILY["schedules"])

    def test_dry_run_prints_the_plan(self):
        code, output = self.main(PERSONAL, "--dry-run")
        self.assertEqual(code, 0)
        self.assertIn("family-mail-parsing: create", output)
        self.assertFalse((self.dir / "home" / "scripts").exists())


if __name__ == "__main__":
    unittest.main()
