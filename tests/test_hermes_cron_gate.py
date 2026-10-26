"""The Milestone 3 gate without a model: its scoring of the calendar tool call
and the reasoning effort it sends."""

import contextlib
import dataclasses
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
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


def turn(tool_calls, content=""):
    return gate.Turn(http_status=200, ttft_s=1.0, total_s=2.0, prompt_tokens=100, completion_tokens=20,
                     reasoning_tokens=None, decode_tok_s=20.0, content=content, tool_calls=tool_calls, error=None)


GOOD_BLOCK = {"processed": [gate.MAIL_KEY], "uncertain": []}


def answer(block, before="One proposal created.\n\n", tag="json"):
    if not isinstance(block, str):
        block = json.dumps(block)
    return f"{before}```{tag}\n{block}\n```\n"


class CallPassesTests(unittest.TestCase):
    def test_the_expected_call_passes(self):
        self.assertTrue(gate.call_passes([call(GOOD_ARGS)]))

    def test_the_same_times_in_utc_pass(self):
        for start, end in (("2026-11-12T14:30:00Z", "2026-11-12T14:40:00Z"),
                           ("2026-11-12t14:30:00.000z", "2026-11-12t14:40:00.000z")):
            with self.subTest(start=start):
                self.assertTrue(gate.call_passes([call(dict(GOOD_ARGS, start=start, end=end))]))

    def test_times_must_be_rfc_3339_date_times(self):
        # Python's fromisoformat takes each of these, with the expected instants.
        for start, end in (("20261112T153000+0100", "20261112T154000+0100"),
                           ("2026-11-12 15:30:00+01:00", "2026-11-12 15:40:00+01:00"),
                           ("2026-W46-4T15:30:00+01:00", "2026-W46-4T15:40:00+01:00"),
                           ("2026-11-12T15:30:00+01:00:00", "2026-11-12T15:40:00+01:00:00"),
                           ("2026-11-12T15:30+01:00", "2026-11-12T15:40+01:00")):
            with self.subTest(start=start):
                self.assertFalse(gate.call_passes([call(dict(GOOD_ARGS, start=start, end=end))]))

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


class BlockErrorTests(unittest.TestCase):
    def test_the_expected_block_passes(self):
        self.assertIsNone(gate.block_error(answer(GOOD_BLOCK)))
        self.assertIsNone(gate.block_error(answer({"uncertain": [], "processed": [gate.MAIL_KEY]}, before="")))

    def test_the_notifier_takes_a_fence_with_or_without_a_json_tag(self):
        for tag in ("json", "JSON", "", " json "):
            with self.subTest(tag=tag):
                self.assertIsNone(gate.block_error(answer(GOOD_BLOCK, tag=tag)))

    def test_only_the_last_block_counts(self):
        bad = answer({"processed": [], "uncertain": []})
        self.assertIsNone(gate.block_error(bad + answer(GOOD_BLOCK)))
        self.assertIsNotNone(gate.block_error(answer(GOOD_BLOCK) + bad))

    def test_an_answer_without_a_complete_block_fails(self):
        for text in ("", "Done.", json.dumps(GOOD_BLOCK), f"```json\n{json.dumps(GOOD_BLOCK)}\n",
                     f"```json\n{json.dumps(GOOD_BLOCK)[:-1]}\n```"):
            with self.subTest(text=text):
                self.assertIsNotNone(gate.block_error(text))

    def test_the_block_must_be_exactly_the_expected_object(self):
        key = gate.MAIL_KEY
        other = "0" * 32
        for block in ([GOOD_BLOCK], "null", {"processed": [key]}, {"uncertain": []},
                      {"processed": [key], "uncertain": [], "notes": ""},
                      {"processed": key, "uncertain": []}, {"processed": [], "uncertain": []},
                      {"processed": [key, key], "uncertain": []}, {"processed": [key.upper()], "uncertain": []},
                      {"processed": [key, other], "uncertain": []}, {"processed": [other, key], "uncertain": []},
                      {"processed": [key, None], "uncertain": []},
                      {"processed": [other], "uncertain": []}, {"processed": [key], "uncertain": None},
                      {"processed": [key], "uncertain": {}},
                      {"processed": [key], "uncertain": [{"key": key, "from": "groep5@school.example",
                                                          "subject": "Tienminutengesprekken groep 5",
                                                          "received": "Thu, 22 Oct 2026 16:05:00 +0200"}]}):
            with self.subTest(block=block):
                self.assertIsNotNone(gate.block_error(answer(block)))


class RunCaseTests(unittest.TestCase):
    def run_turns(self, *turns):
        fixture = gate.Fixture(system="system", tools=[gate.CALENDAR_TOOL], hermes_tool_count=0)
        sent = []

        def stream_turn(model, max_tokens, effort, tools, messages):
            sent.append(json.loads(json.dumps(messages)))
            return turns[len(sent) - 1]

        with mock.patch.object(gate, "stream_turn", side_effect=stream_turn):
            return gate.run_case(fixture, "spark/dsv41", 1024, "high", 1, "cold"), sent

    def test_the_call_then_the_block_passes(self):
        result, sent = self.run_turns(turn([call(GOOD_ARGS)]), turn([], answer(GOOD_BLOCK)))
        self.assertEqual((result.passed, result.first_response_passed, result.failure, result.retries),
                         (True, True, None, 0))
        self.assertEqual(sent[1][-1], {"role": "tool", "tool_call_id": "call-1", "name": "create_calendar_event",
                                        "content": gate.proposal_reply(call(GOOD_ARGS))})

    def test_the_tool_answers_like_gcal_proposals(self):
        event_id = hashlib.sha256(f"{gate.MAIL_KEY}|2026-11-12T14:30:00Z|1".encode()).hexdigest()[:32]
        self.assertEqual(gate.proposal_reply(call(GOOD_ARGS)),
                         f"Proposal {event_id} for mail {gate.MAIL_KEY} is in the Proposals calendar: "
                         "Tienminutengesprek groep 5 (2026-11-12T15:30:00+01:00 to 2026-11-12T15:40:00+01:00); "
                         "both parents are invited.")

    def test_the_right_call_without_a_valid_block_fails(self):
        for content in ("Done.", answer({"processed": [gate.MAIL_KEY]})):
            with self.subTest(content=content):
                result, _ = self.run_turns(turn([call(GOOD_ARGS)]), turn([], content))
                self.assertFalse(result.passed)
                self.assertFalse(result.first_response_passed)
                self.assertTrue(result.failure.startswith("block: "))

    def test_a_block_without_a_call_fails(self):
        result, sent = self.run_turns(turn([], answer(GOOD_BLOCK)))
        self.assertFalse(result.passed)
        self.assertTrue(result.failure.startswith("call: "))
        self.assertEqual(len(sent), 1)

    def test_a_second_call_fails(self):
        result, _ = self.run_turns(turn([call(GOOD_ARGS)]), turn([call(GOOD_ARGS)], answer(GOOD_BLOCK)))
        self.assertFalse(result.passed)
        self.assertTrue(result.failure.startswith("call: "))

    def test_a_wrong_call_fails_without_a_tool_answer(self):
        result, sent = self.run_turns(turn([call(dict(GOOD_ARGS, n=2))]), turn([], answer(GOOD_BLOCK)))
        self.assertFalse(result.passed)
        self.assertEqual(len(sent), 1)

    def test_a_retry_after_an_unknown_tool_passes_but_not_on_the_first_response(self):
        unknown = {"id": "call-0", "name": "create_proposal", "arguments": json.dumps(GOOD_ARGS)}
        result, sent = self.run_turns(turn([unknown]), turn([call(GOOD_ARGS)]), turn([], answer(GOOD_BLOCK)))
        self.assertEqual((result.passed, result.first_response_passed, result.retries), (True, False, 1))
        self.assertTrue(sent[1][-1]["content"].startswith("Tool 'create_proposal' does not exist."))

    def test_an_http_error_fails_the_run(self):
        error = dataclasses.replace(turn([]), http_status=400, error="bad request")
        result, _ = self.run_turns(turn([call(GOOD_ARGS)]), error)
        self.assertEqual((result.passed, result.failure), (False, "http 400"))

    def test_the_summary_counts_failure_kinds(self):
        results = [self.run_turns(turn([call(GOOD_ARGS)]), turn([], content))[0]
                   for content in (answer(GOOD_BLOCK), "Done.", "Done.")]
        summary = gate.summarize(results)
        self.assertEqual((summary["passed"], summary["first_response_passed"]), (1, 1))
        self.assertEqual(summary["failures"], {"block: no fenced JSON block": 2})
        self.assertFalse(summary["gate"])


class MailFixtureTests(unittest.TestCase):
    def test_the_model_sees_the_mail_key_and_no_message_id(self):
        self.assertIn(f"Mail-Key: {gate.MAIL_KEY}\n", gate.TASK)
        self.assertNotIn("Message-ID", gate.TASK)
        self.assertNotIn(gate.MESSAGE_ID, gate.TASK)


class ReasoningEffortTests(unittest.TestCase):
    def run_gate(self, *flags):
        fixture = gate.Fixture(system="system", tools=[gate.CALENDAR_TOOL], hermes_tool_count=0)
        passed = gate.RunResult(run=0, turns=[turn([call(GOOD_ARGS)])], first_response_passed=True, passed=True)
        argv = ["hermes-cron-gate.py", "--model", "spark/dsv41", "--runs", "2", *flags]
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(gate, "configured_reasoning_effort", return_value="high", create=True) as configured,
            mock.patch.object(gate, "load_fixture", return_value=fixture),
            mock.patch.object(gate, "run_case", return_value=passed) as run_case,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(gate.main(), 0)
        return [c.args[3] for c in run_case.call_args_list], configured

    def test_without_the_flag_the_gate_sends_the_configured_effort(self):
        efforts, configured = self.run_gate()
        configured.assert_called_once_with("spark/dsv41")
        self.assertEqual(efforts, ["high"] * 3)

    def test_the_flag_overrides_the_configured_effort(self):
        efforts, configured = self.run_gate("--reasoning-effort", "low")
        configured.assert_not_called()
        self.assertEqual(efforts, ["low"] * 3)

    def test_an_empty_flag_sends_no_effort(self):
        efforts, configured = self.run_gate("--reasoning-effort", "")
        configured.assert_not_called()
        self.assertEqual(efforts, [""] * 3)


def hermes_importable():
    try:
        import agent.reasoning_effort  # noqa: F401
        import hermes_cli.config  # noqa: F401
        import hermes_constants  # noqa: F401
    except ImportError:
        return False
    return True


@unittest.skipUnless(hermes_importable(), "needs a Hermes Python (hermesVenv) on sys.path")
class ConfiguredReasoningEffortTests(unittest.TestCase):
    def test_the_per_model_override_then_the_global_effort(self):
        with tempfile.TemporaryDirectory() as home:
            Path(home, "config.yaml").write_text(
                "agent:\n  reasoning_effort: medium\n  reasoning_overrides:\n    spark/dsv41: high\n")
            with mock.patch.dict(os.environ, {"HERMES_HOME": home}):
                self.assertEqual(gate.configured_reasoning_effort("spark/dsv41"), "high")
                self.assertEqual(gate.configured_reasoning_effort("deepseek/deepseek-v4.1-flash"), "medium")



if __name__ == "__main__":
    unittest.main()
