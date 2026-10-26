import asyncio
import hashlib
import json
import unittest
import urllib.error
from unittest import mock

from hermes_family import gcal_mcp
from hermes_family.google import Api, load_family
from hermes_family.state import State
from tests.support import FAMILY, FakeNet, fixture, temp_dir, write_json

CALENDAR = fixture("calendar.json")
KEY = "76daed97cd1135f83d9772ef841c73e3"
PROPOSALS_EVENTS = "/calendars/proposals%40group.calendar.google.com/events"


def expected_id(start: str, n: int) -> str:
    return hashlib.sha256(f"{KEY}|{start}|{n}".encode()).hexdigest()[:32]


class Server:
    """The MCP server as Hermes sees it: list_tools and call_tool."""

    def __init__(self, test: unittest.TestCase, mode: str, fake: FakeNet):
        fake.patch(test)
        directory = temp_dir(test)
        family = load_family(write_json(directory / "family.json", FAMILY))
        self.state = State(directory)
        self.server = gcal_mcp.build_server(mode, lambda: Api("ya29.test-token"), lambda: family, self.state)

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
        self.assertEqual(set(schema["required"]), {"title", "start", "end", "mail_key", "n"})
        self.assertEqual(schema["properties"]["n"]["type"], "integer")

    def test_inserts_with_the_appointment_id_both_parents_invited_and_updates_sent(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, CALENDAR["created"])
        text = Server(self, "proposals", fake).call(
            "create_proposal", title="Tienminutengesprek Kind A", start="2026-11-12T15:30:00+01:00",
            end="2026-11-12T15:40:00+01:00", location="Lokaal 3", mail_key=KEY, n=1)
        self.assertIn("Created proposal", text)
        (call,) = fake.calls
        self.assertEqual(call.params, {"sendUpdates": "all"})
        self.assertEqual(call.body["id"], expected_id("2026-11-12T14:30:00Z", 1))
        self.assertEqual(call.body["attendees"], [{"email": "ouder1@example.org"}, {"email": "ouder2@example.org"}])
        self.assertEqual(call.body["start"], {"dateTime": "2026-11-12T15:30:00+01:00"})
        self.assertEqual(call.body["location"], "Lokaal 3")

    def test_conflict_409_is_success(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, (409, CALENDAR["conflict"]))
        server = Server(self, "proposals", fake)
        text = server.call("create_proposal", title="Ouderavond", start="2026-11-12T19:00:00+01:00",
                           end="2026-11-12T20:00:00+01:00", mail_key=KEY, n=1)
        self.assertEqual(text,
                         f"Proposal {expected_id('2026-11-12T18:00:00Z', 1)} for mail {KEY} already exists; nothing to do.")
        self.assertEqual(server.state.proposal_failures(), {})

    def test_two_appointments_at_the_same_time_in_one_mail_get_two_events(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, CALENDAR["created"])
        server = Server(self, "proposals", fake)
        for n, title in ((1, "Gesprek Kind A"), (2, "Gesprek Kind B")):
            server.call("create_proposal", title=title, start="2026-11-12T15:30:00+01:00",
                        end="2026-11-12T15:40:00+01:00", mail_key=KEY, n=n)
        server.call("create_proposal", title="Sluitingsdag opvang", start="2026-11-06", end="2026-11-06",
                    mail_key=KEY, n=3)
        ids = [call.body["id"] for call in fake.calls]
        self.assertEqual(ids, [expected_id("2026-11-12T14:30:00Z", 1), expected_id("2026-11-12T14:30:00Z", 2),
                               expected_id("2026-11-06", 3)])
        self.assertEqual(len(set(ids)), 3)
        self.assertTrue(all(len(i) == 32 and set(i) <= set("0123456789abcdef") for i in ids))

    def test_the_same_instant_written_another_way_is_one_event(self):
        created = set()

        def calendar(call):
            if call.body["id"] in created:
                return 409, CALENDAR["conflict"]
            created.add(call.body["id"])
            return CALENDAR["created"]

        server = Server(self, "proposals", FakeNet().on("POST", PROPOSALS_EVENTS, calendar))
        first = server.call("create_proposal", title="Ouderavond", start="2026-11-12T19:00:00+01:00",
                            end="2026-11-12T20:00:00+01:00", mail_key=KEY, n=1)
        again = server.call("create_proposal", title="Ouderavond school", start="2026-11-12T19:00+01:00",
                            end="2026-11-12T20:30:00.000+01:00", mail_key=KEY, n=1)
        self.assertIn("Created proposal", first)
        self.assertIn("already exists", again)
        self.assertEqual(created, {expected_id("2026-11-12T18:00:00Z", 1)})

    def test_all_day_end_date_is_inclusive(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, CALENDAR["created"])
        Server(self, "proposals", fake).call(
            "create_proposal", title="Sluitingsdag opvang", start="2026-11-06", end="2026-11-06", mail_key=KEY, n=1)
        self.assertEqual(fake.calls[0].body["start"], {"date": "2026-11-06"})
        self.assertEqual(fake.calls[0].body["end"], {"date": "2026-11-07"})

    def test_both_offsets_of_the_fall_back_hour_are_accepted(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, CALENDAR["created"])
        server = Server(self, "proposals", fake)
        server.call("create_proposal", title="Nachtwandeling", start="2026-10-25T02:30:00+02:00",
                    end="2026-10-25T02:45:00+02:00", mail_key=KEY, n=1)
        server.call("create_proposal", title="Nachtwandeling", start="2026-10-25T02:30:00+01:00",
                    end="2026-10-25T02:45:00+01:00", mail_key=KEY, n=2)
        self.assertEqual([call.body["id"] for call in fake.calls],
                         [expected_id("2026-10-25T00:30:00Z", 1), expected_id("2026-10-25T01:30:00Z", 2)])

    def test_rejects_an_offset_that_is_not_amsterdams_without_calling_google(self):
        fake = FakeNet()
        server = Server(self, "proposals", fake)
        for start, end in [
            ("2026-11-12T15:30:00+02:00", "2026-11-12T16:00:00+02:00"),
            ("2026-11-12T15:30:00+01:00", "2026-11-12T16:00:00+02:00"),
            ("2026-11-12T14:30:00Z", "2026-11-12T15:00:00Z"),
            ("2026-06-12T15:30:00+01:00", "2026-06-12T16:00:00+01:00"),
            ("2026-03-29T02:30:00+01:00", "2026-03-29T03:30:00+02:00"),
        ]:
            with self.assertRaises(Exception) as caught:
                server.call("create_proposal", title="X", start=start, end=end, mail_key=KEY, n=1)
            self.assertIn("Europe/Amsterdam offset", str(caught.exception))
        self.assertEqual(fake.calls, [])
        self.assertEqual(server.state.proposal_failures(), {})

    def test_rejects_bad_input_without_calling_google(self):
        fake = FakeNet()
        server = Server(self, "proposals", fake)
        base = dict(title="X", start="2026-11-12T15:30:00+01:00", end="2026-11-12T16:00:00+01:00", mail_key=KEY, n=1)
        for arguments, message in [
            (dict(mail_key="&lt;abc&gt;"), "mail_key"),
            (dict(start="2026-11-12T15:30:00"), "without an offset"),
            (dict(end="2026-11-12T16:00:00"), "without an offset"),
            (dict(start="12 november 15:30"), "RFC 3339"),
            (dict(n=0), "position in the mail"),
            (dict(end="2026-11-12T15:00:00+01:00"), "after start"),
            (dict(end="2026-11-13"), "both be dates"),
        ]:
            with self.assertRaises(Exception) as caught:
                server.call("create_proposal", **{**base, **arguments})
            self.assertIn(message, str(caught.exception))
        without_n = {key: value for key, value in base.items() if key != "n"}
        with self.assertRaises(Exception) as caught:
            server.call("create_proposal", **without_n)
        self.assertIn("n\n  Field required", str(caught.exception))
        self.assertEqual(fake.calls, [])
        self.assertEqual(server.state.proposal_failures(), {})

    def test_a_google_error_fails_the_call_and_keeps_the_mail_retryable(self):
        fake = FakeNet().on("POST", PROPOSALS_EVENTS, (403, {"error": {"message": "forbidden"}}))
        server = Server(self, "proposals", fake)
        with self.assertRaises(Exception) as caught:
            server.call("create_proposal", title="X", start="2026-11-12T15:30:00+01:00",
                        end="2026-11-12T16:00:00+01:00", mail_key=KEY, n=1)
        self.assertIn("HTTP 403", str(caught.exception))
        self.assertEqual(set(server.state.proposal_failures()), {KEY})

    def test_no_answer_from_google_keeps_the_mail_retryable(self):
        def unreachable(call):
            raise urllib.error.URLError("timed out")

        server = Server(self, "proposals", FakeNet().on("POST", PROPOSALS_EVENTS, unreachable))
        with self.assertRaises(Exception):
            server.call("create_proposal", title="X", start="2026-11-12T15:30:00+01:00",
                        end="2026-11-12T16:00:00+01:00", mail_key=KEY, n=1)
        self.assertEqual(set(server.state.proposal_failures()), {KEY})


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

    def test_sorts_by_instant_with_all_day_events_at_local_midnight(self):
        family = {"items": [
            {"summary": "Zwemles Kind A", "start": {"dateTime": "2026-10-28T16:00:00+01:00"}},
            {"summary": "Studiedag", "start": {"date": "2026-10-28"}},
        ]}
        personal = {"items": [
            {"summary": "Vroege call", "start": {"dateTime": "2026-10-27T23:30:00Z"}},
            {"summary": "Overleg", "start": {"dateTime": "2026-10-28T14:30:00Z"}},
        ]}
        fake = (FakeNet()
                .on("GET", "/calendars/family%40group.calendar.google.com/events", family)
                .on("GET", "/calendars/ouder1%40example.org/events", personal))
        result = json.loads(Server(self, "read", fake).call("list_events", time_min="2026-10-28",
                                                            time_max="2026-10-29"))
        self.assertEqual([e["title"] for e in result["events"]], ["Studiedag", "Vroege call", "Overleg", "Zwemles Kind A"])

    def test_personal_calendar_not_shared_yet_is_reported_not_fatal(self):
        text = Server(self, "read", self.fake((404, CALENDAR["not_found"]))).call(
            "list_events", time_min="2026-10-28", time_max="2026-10-29")
        result = json.loads(text)
        self.assertEqual(len(result["events"]), 1)
        self.assertIn("personal", result["unavailable"][0])

    def test_personal_calendar_without_answer_is_reported_not_fatal(self):
        def unreachable(call):
            raise urllib.error.URLError("timed out")

        text = Server(self, "read", self.fake(unreachable)).call(
            "list_events", time_min="2026-10-28", time_max="2026-10-29")
        result = json.loads(text)
        self.assertEqual([e["title"] for e in result["events"]], ["Zwemles Kind A"])
        self.assertEqual(len(result["unavailable"]), 1)
        self.assertIn("personal", result["unavailable"][0])

    def test_family_calendar_without_answer_fails_the_call(self):
        def unreachable(call):
            raise ConnectionRefusedError("refused")

        fake = (FakeNet()
                .on("GET", "/calendars/family%40group.calendar.google.com/events", unreachable)
                .on("GET", "/calendars/ouder1%40example.org/events", CALENDAR["personal"]))
        with self.assertRaises(Exception) as caught:
            Server(self, "read", fake).call("list_events", time_min="2026-10-28", time_max="2026-10-29")
        self.assertIn("refused", str(caught.exception))

    def test_range_is_capped(self):
        with self.assertRaises(Exception) as caught:
            Server(self, "read", FakeNet()).call("list_events", time_min="2026-01-01", time_max="2026-06-01")
        self.assertIn("62 days", str(caught.exception))


class FamilyTest(unittest.TestCase):
    """The server for jobs that answer in the family group: the family calendar only."""

    def test_offers_only_list_events(self):
        self.assertEqual(set(Server(self, "family", FakeNet()).tools()), {"list_events"})

    def test_never_reads_or_returns_the_personal_calendar(self):
        fake = (FakeNet()
                .on("GET", "/calendars/family%40group.calendar.google.com/events", CALENDAR["school_day"])
                .on("GET", "/calendars/ouder1%40example.org/events", CALENDAR["personal"]))
        result = json.loads(Server(self, "family", fake).call("list_events", time_min="2026-10-28",
                                                              time_max="2026-10-29"))
        self.assertEqual([(e["calendar"], e["title"]) for e in result["events"]], [("family", "Zwemles Kind A")])
        self.assertNotIn("unavailable", result)
        self.assertEqual(fake.matching("GET", "ouder1"), [])
        self.assertEqual(len(fake.calls), 1)

    def test_main_accepts_family_mode(self):
        directory = temp_dir(self)
        family = write_json(directory / "family.json", FAMILY)
        credential = write_json(directory / "credential.json", {})
        with mock.patch.object(gcal_mcp, "build_server") as build:
            self.assertEqual(gcal_mcp.main(["family", "--credential", str(credential), "--family", str(family),
                                            "--state-dir", str(directory)]), 0)
        self.assertEqual(build.call_args.args[0], "family")


if __name__ == "__main__":
    unittest.main()
