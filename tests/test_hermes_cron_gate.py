"""The Milestone 3 gate's scoring of a model's calendar tool call, without a model."""

import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[1]


def load_gate():
    spec = importlib.util.spec_from_file_location("hermes_cron_gate", REPO / "scripts" / "hermes-cron-gate.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


gate = load_gate()

GOOD_ARGS = {
    "title": "Tienminutengesprek groep 5",
    "start": "2026-11-12T15:30:00+01:00",
    "end": "2026-11-12T15:40:00+01:00",
    "location": "lokaal 3",
    "mail_key": gate.MAIL_KEY,
    "n": 1,
}


def call(arguments):
    if not isinstance(arguments, str):
        arguments = json.dumps(arguments)
    return {"id": "call-1", "name": "create_calendar_event", "arguments": arguments}


def turn(tool_calls):
    return gate.Turn(http_status=200, ttft_s=1.0, total_s=2.0, prompt_tokens=100, completion_tokens=20,
                     reasoning_tokens=None, decode_tok_s=20.0, content="", tool_calls=tool_calls, error=None)


class CallPassesTests(unittest.TestCase):
    def test_the_expected_call_passes(self):
        self.assertTrue(gate.call_passes([call(GOOD_ARGS)]))

    def test_the_same_times_in_utc_pass(self):
        args = dict(GOOD_ARGS, start="2026-11-12T14:30:00Z", end="2026-11-12T14:40:00Z")
        self.assertTrue(gate.call_passes([call(args)]))

    def test_every_required_argument_must_be_there(self):
        for missing in ("title", "start", "end", "mail_key", "n"):
            with self.subTest(missing=missing):
                args = {k: v for k, v in GOOD_ARGS.items() if k != missing}
                self.assertFalse(gate.call_passes([call(args)]))

    def test_required_strings_must_be_strings(self):
        for key, value in (("title", ""), ("title", "   "), ("title", 5), ("end", None), ("end", 1794501600)):
            with self.subTest(key=key, value=value):
                self.assertFalse(gate.call_passes([call(dict(GOOD_ARGS, **{key: value}))]))

    def test_the_end_must_be_ten_minutes_after_the_start(self):
        for end in ("2026-11-12T15:30:00+01:00", "2026-11-12T16:30:00+01:00", "2026-11-12T15:40:00",
                    "2026-11-12T15:40:00+02:00", "15:40"):
            with self.subTest(end=end):
                self.assertFalse(gate.call_passes([call(dict(GOOD_ARGS, end=end))]))

    def test_non_object_arguments_fail_without_raising(self):
        for arguments in ("null", '"2026-11-12T15:30:00+01:00"', "[]", '[{"n": 1}]', "1", "true"):
            with self.subTest(arguments=arguments):
                self.assertFalse(gate.call_passes([call(arguments)]))

    def test_non_object_arguments_are_a_failed_run_not_an_aborted_gate(self):
        fixture = gate.Fixture(system="system", tools=[gate.CALENDAR_TOOL], hermes_tool_count=0)
        with mock.patch.object(gate, "stream_turn", return_value=turn([call("null")])):
            result = gate.run_case(fixture, "spark/dsv41", 1024, None, 1, "warm")
        self.assertFalse(result.passed)
        self.assertFalse(result.first_response_passed)


if __name__ == "__main__":
    unittest.main()
