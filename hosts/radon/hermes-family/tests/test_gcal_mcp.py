import asyncio
import hashlib
import json
import unittest

from hermes_family import gcal_mcp
from hermes_family.google import Api, load_family
from tests.support import FAMILY, FakeNet, fixture, temp_dir, write_json

CALENDAR = fixture("calendar.json")
KEY = "76daed97cd1135f83d9772ef841c73e3"
PROPOSALS_EVENTS = "/calendars/proposals%40group.calendar.google.com/events"


def expected_id(start: str) -> str:
    return hashlib.sha256(f"{KEY}|{start}".encode()).hexdigest()[:32]


class Server:
    """The MCP server as Hermes sees it: list_tools and call_tool."""

    def __init__(self, test: unittest.TestCase, mode: str, fake: FakeNet):
        fake.patch(test)
        family = load_family(write_json(temp_dir(test) / "family.json", FAMILY))
        self.server = gcal_mcp.build_server(mode, lambda: Api("ya29.test-token"), lambda: family)

    def tools(self) -> dict:
        return {tool.name: tool for tool in asyncio.run(self.server.list_tools())}

    def call(self, name: str, **arguments) -> str:
        result = asyncio.run(self.server.call_tool(name, arguments))
        content = result[0] if isinstance(result, tuple) else result
        return content[0].text


class ProposalsTest(unittest.TestCase):
    def test_offers_only_create_proposal(self):
        server = Server(self, "proposals", FakeNet())
        tools = server.tools()
        self.assertEqual(set(tools), {"create_proposal"})
        schema = tools["create_proposal"].inputSchema
        self.assertEqual(set(schema["required"]), {"title", "start", "end", "mail_key"})

    def test_inserts_with_the_appointment_id_both_parents_invited_and_updates_sent(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, CALENDAR["created"])
        text = Server(self, "proposals", fake).call(
            "create_proposal", title="Tienminutengesprek Kind A", start="2026-11-12T15:30:00",
            end="2026-11-12T15:40:00", location="Lokaal 3", mail_key=KEY)
        self.assertIn("Created proposal", text)
        (call,) = fake.calls
        self.assertEqual(call.params, {"sendUpdates": "all"})
        self.assertEqual(call.body["id"], expected_id("2026-11-12T15:30"))
        self.assertEqual(call.body["attendees"], [{"email": "ouder1@example.org"}, {"email": "ouder2@example.org"}])
        self.assertEqual(call.body["start"], {"dateTime": "2026-11-12T15:30:00", "timeZone": "Europe/Amsterdam"})
        self.assertEqual(call.body["location"], "Lokaal 3")

    def test_conflict_409_is_success(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, (409, CALENDAR["conflict"]))
        text = Server(self, "proposals", fake).call(
            "create_proposal", title="Ouderavond", start="2026-11-12T19:00:00", end="2026-11-12T20:00:00", mail_key=KEY)
        self.assertEqual(text, f"Proposal {expected_id('2026-11-12T19:00')} for mail {KEY} already exists; nothing to do.")

    def test_two_appointments_in_one_mail_get_two_events(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, CALENDAR["created"])
        server = Server(self, "proposals", fake)
        server.call("create_proposal", title="Ouderavond", start="2026-11-12T19:00:00", end="2026-11-12T20:00:00",
                    mail_key=KEY)
        server.call("create_proposal", title="Sluitingsdag opvang", start="2026-11-06", end="2026-11-06", mail_key=KEY)
        ids = [call.body["id"] for call in fake.calls]
        self.assertEqual(ids, [expected_id("2026-11-12T19:00"), expected_id("2026-11-06")])
        self.assertNotEqual(ids[0], ids[1])
        self.assertTrue(all(len(i) == 32 and set(i) <= set("0123456789abcdef") for i in ids))

    def test_same_appointment_twice_is_one_event(self):
        created = set()

        def calendar(call):
            if call.body["id"] in created:
                return 409, CALENDAR["conflict"]
            created.add(call.body["id"])
            return CALENDAR["created"]

        server = Server(self, "proposals", FakeNet().on("POST", PROPOSALS_EVENTS, calendar))
        first = server.call("create_proposal", title="Ouderavond", start="2026-11-12T19:00:00",
                            end="2026-11-12T20:00:00", mail_key=KEY)
        again = server.call("create_proposal", title="Ouderavond school", start="2026-11-12T19:00:00+01:00",
                            end="2026-11-12T20:30:00+01:00", mail_key=KEY)
        self.assertIn("Created proposal", first)
        self.assertIn("already exists", again)
        self.assertEqual(created, {expected_id("2026-11-12T19:00")})

    def test_all_day_end_date_is_inclusive(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, CALENDAR["created"])
        Server(self, "proposals", fake).call(
            "create_proposal", title="Sluitingsdag opvang", start="2026-11-06", end="2026-11-06", mail_key=KEY)
        self.assertEqual(fake.calls[0].body["start"], {"date": "2026-11-06"})
        self.assertEqual(fake.calls[0].body["end"], {"date": "2026-11-07"})

    def test_rejects_bad_input_without_calling_google(self):
        fake = FakeNet()
        server = Server(self, "proposals", fake)
        for arguments, message in [
            (dict(mail_key="&lt;abc&gt;"), "mail_key"),
            (dict(end="2026-11-12T15:00:00"), "after start"),
            (dict(end="2026-11-13"), "both be dates"),
        ]:
            base = dict(title="X", start="2026-11-12T15:30:00", end="2026-11-12T16:00:00", mail_key=KEY)
            with self.assertRaises(Exception) as caught:
                server.call("create_proposal", **{**base, **arguments})
            self.assertIn(message, str(caught.exception))
        self.assertEqual(fake.calls, [])

    def test_other_google_errors_fail_the_call(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, (403, {"error": {"message": "forbidden"}}))
        with self.assertRaises(Exception) as caught:
            Server(self, "proposals", fake).call(
                "create_proposal", title="X", start="2026-11-12T15:30:00", end="2026-11-12T16:00:00", mail_key=KEY)
        self.assertIn("HTTP 403", str(caught.exception))


class ReadTest(unittest.TestCase):
    def fake(self, personal) -> FakeNet:
        return (FakeNet()
                .on("GET", "/calendars/family%40group.calendar.google.com/events", CALENDAR["school_day"])
                .on("GET", "/calendars/ouder1%40example.org/events", personal))

    def test_offers_only_list_events(self):
        self.assertEqual(set(Server(self, "read", FakeNet()).tools()), {"list_events"})

    def test_merges_family_and_personal_sorted_without_cancelled_events(self):
        fake = self.fake(CALENDAR["personal"])
        text = Server(self, "read", fake).call("list_events", time_min="2026-10-28", time_max="2026-10-29")
        result = json.loads(text)
        self.assertEqual([(e["calendar"], e["title"]) for e in result["events"]],
                         [("personal", "Tandarts"), ("family", "Zwemles Kind A")])
        self.assertEqual(fake.calls[0].params["timeMin"], "2026-10-28T00:00:00+01:00")
        self.assertTrue(all(call.method == "GET" for call in fake.calls))

    def test_personal_calendar_not_shared_yet_is_reported_not_fatal(self):
        text = Server(self, "read", self.fake((404, CALENDAR["not_found"]))).call(
            "list_events", time_min="2026-10-28", time_max="2026-10-29")
        result = json.loads(text)
        self.assertEqual(len(result["events"]), 1)
        self.assertIn("personal", result["unavailable"][0])

    def test_range_is_capped(self):
        with self.assertRaises(Exception) as caught:
            Server(self, "read", FakeNet()).call("list_events", time_min="2026-01-01", time_max="2026-06-01")
        self.assertIn("62 days", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
