import io
import json
import unittest
from contextlib import redirect_stdout

from hermes_family import pickup
from tests.support import CREDENTIAL, FAMILY, FakeNet, fixture, temp_dir, token_route, write_json

CALENDAR = fixture("calendar.json")


class PickupTest(unittest.TestCase):
    def setUp(self):
        self.dir = temp_dir(self)
        self.credential = write_json(self.dir / "read.json", CREDENTIAL)
        self.family = write_json(self.dir / "family.json", FAMILY)
        self.run_log = self.dir / "runs.jsonl"
        self.fake = token_route(FakeNet())

    def run_main(self, day: str, events_response) -> str:
        self.fake.on("GET", "/calendars/family%40group.calendar.google.com/events", events_response).patch(self)
        out = io.StringIO()
        with redirect_stdout(out):
            code = pickup.main(["--credential", str(self.credential), "--family", str(self.family),
                                "--run-log", str(self.run_log), "--dry-run", "--date", day])
        self.assertEqual(code, 0)
        return out.getvalue()

    def test_school_day_wednesday_asks_the_question(self):
        self.assertEqual(self.run_main("2026-10-28", CALENDAR["school_day"]), pickup.QUESTION + "\n")
        query = self.fake.matching("GET", "/events")[0].params
        self.assertEqual(query["timeMin"], "2026-10-28T00:00:00+01:00")
        self.assertEqual(query["timeMax"], "2026-10-29T00:00:00+01:00")
        self.assertEqual(query["singleEvents"], "true")

    def test_saturday_prints_nothing_and_reads_no_calendar(self):
        self.assertEqual(self.run_main("2026-10-31", CALENDAR["school_day"]), "")
        self.assertEqual(self.fake.calls, [])

    def test_school_holiday_prints_nothing(self):
        self.assertEqual(self.run_main("2026-10-21", CALENDAR["holiday"]), "")

    def test_cancelled_holiday_event_does_not_count(self):
        cancelled = {"items": [dict(CALENDAR["holiday"]["items"][0], status="cancelled")]}
        self.assertEqual(self.run_main("2026-10-21", cancelled), pickup.QUESTION + "\n")

    def test_unreadable_calendar_still_asks_and_logs(self):
        self.assertEqual(self.run_main("2026-10-28", (403, CALENDAR["not_found"])), pickup.QUESTION + "\n")
        row = json.loads(self.run_log.read_text())
        self.assertEqual((row["job"], row["status"]), ("family-pickup", "failed"))
        self.assertIn("HTTP 403", row["error"])

    def test_holiday_words(self):
        pattern = pickup.re.compile(pickup.HOLIDAY_PATTERN, pickup.re.IGNORECASE)
        for title in ("Kerstvakantie", "Studiedag groep 5", "Vrije dag", "School holiday"):
            self.assertTrue(pickup.is_school_holiday([{"summary": title}], pattern), title)
        for title in ("Vrijdagmiddag borrel", "Zwemles"):
            self.assertFalse(pickup.is_school_holiday([{"summary": title}], pattern), title)


if __name__ == "__main__":
    unittest.main()
