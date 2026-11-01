import io
import json
import threading
import unittest
from contextlib import redirect_stderr
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

from hermes_family import model_health
from tests.support import FAMILY, FakeNet, temp_dir, write_json


class ModelHealthTest(unittest.TestCase):
    def setUp(self):
        self.dir = temp_dir(self)
        self.env = self.dir / "env"
        self.env.write_text('TELEGRAM_BOT_TOKEN="123:sentinel_secret"\nTELEGRAM_ALLOWED_USERS=123456789\n')
        self.family = write_json(self.dir / "family.json", FAMILY)
        self.state = self.dir / "health"
        self.healthy = True
        self.delivery = True
        self.private = True
        self.fake = FakeNet().on("POST", "/chat/completions", lambda _: (
            {"model": "dsv41", "choices": [{"message": {"content": "OK"}}]}
            if self.healthy else (502, {"error": "down"})))
        self.fake.on("POST", "/getChat", lambda _: {"ok": True, "result": {
            "id": 123456789, "type": "private" if self.private else "supergroup"}})
        self.fake.on("POST", "/sendMessage", lambda _: (
            {"ok": True, "result": {"chat": {"id": 123456789, "type": "private"}}}
            if self.delivery else (429, {"ok": False, "parameters": {"retry_after": 600}})))
        self.fake.patch(self)

    def tick(self, now):
        with mock.patch.object(model_health.time, "time", return_value=now):
            return model_health.main(["--env-file", str(self.env), "--family", str(self.family),
                                      "--state-dir", str(self.state), "--base-url", "https://ai.example/v1",
                                      "--model", "spark/dsv41"])

    def messages(self):
        return self.fake.matching("POST", "/sendMessage")

    def test_sustained_outage_alerts_once_then_sends_one_recovery(self):
        self.tick(0)
        self.healthy = False
        for now in (300, 600, 1199):
            self.tick(now)
        self.assertEqual(self.messages(), [])
        self.tick(1200)
        self.tick(1500)
        self.assertEqual(len(self.messages()), 1)
        self.assertEqual(self.messages()[0].body["chat_id"], "123456789")
        self.assertIn("15 minuten", self.messages()[0].body["text"])
        self.healthy = True
        self.tick(1800)
        self.tick(2100)
        self.assertEqual(len(self.messages()), 2)
        self.assertIn("weer bereikbaar", self.messages()[1].body["text"])

    def test_brief_failure_and_recovery_before_delivery_send_nothing(self):
        self.healthy = False
        self.tick(0)
        self.tick(899)
        self.healthy = True
        self.tick(900)
        self.assertEqual(self.messages(), [])

    def test_failed_delivery_retries_after_telegram_delay_and_recovery_retries(self):
        self.healthy = False
        self.delivery = False
        self.tick(0)
        self.assertEqual(self.tick(900), 1)
        self.tick(1200)
        self.assertEqual(len(self.messages()), 1)
        self.delivery = True
        self.tick(1500)
        self.tick(1800)
        self.assertEqual(len(self.messages()), 2)
        self.healthy = True
        self.delivery = False
        self.assertEqual(self.tick(2100), 1)
        self.delivery = True
        self.tick(2700)
        self.tick(3000)
        self.assertEqual(len(self.messages()), 4)

    def test_group_or_unallowlisted_target_never_receives_an_alert(self):
        for target in ("telegram:-1001234567890", "telegram:555", "telegram", "signal:123456789"):
            with self.subTest(target=target):
                write_json(self.family, {**FAMILY, "personal_deliver": target})
                self.assertEqual(self.tick(0), 1)
        write_json(self.family, FAMILY)
        self.healthy = False
        self.private = False
        self.tick(0)
        self.assertEqual(self.tick(900), 1)
        self.assertEqual(self.messages(), [])

    def test_cooldown_survives_recovery_before_an_unsent_outage(self):
        self.fake.routes[-1] = ("POST", "/sendMessage", (
            429, {"ok": False, "parameters": {"retry_after": 3600}}))
        self.healthy = False
        self.tick(0)
        self.tick(900)
        self.healthy = True
        self.tick(1200)
        self.healthy = False
        self.tick(1500)
        self.tick(2400)
        self.assertEqual(len(self.messages()), 1)
        self.tick(4500)
        self.assertEqual(len(self.messages()), 2)

    def test_cooldown_starts_when_telegram_returns_not_when_probe_started(self):
        self.healthy = False
        self.tick(0)
        with mock.patch.object(model_health.time, "time", side_effect=[900, 940]):
            self.delivery = False
            self.assertEqual(model_health.main([
                "--env-file", str(self.env), "--family", str(self.family),
                "--state-dir", str(self.state), "--base-url", "https://ai.example/v1",
                "--model", "spark/dsv41"]), 1)
        self.delivery = True
        self.tick(1500)
        self.assertEqual(len(self.messages()), 1)
        self.tick(1540)
        self.assertEqual(len(self.messages()), 2)

    def test_http_or_telegram_errors_never_print_the_token(self):
        self.healthy = False
        self.tick(0)
        with mock.patch.object(model_health, "notify", side_effect=OSError(
                "https://api.telegram.org/bot123:sentinel_secret/sendMessage")):
            errors = io.StringIO()
            with redirect_stderr(errors):
                self.assertEqual(self.tick(900), 1)
        self.assertNotIn("sentinel_secret", errors.getvalue())
        self.assertNotIn("sentinel_secret", (self.state / "model-health.json").read_text())

    def test_a_different_model_or_blank_reply_is_not_healthy(self):
        for response in (
            {"model": "cloud/fallback", "choices": [{"message": {"content": "OK"}}]},
            {"model": "dsv41", "choices": [{"message": {"content": ""}}]},
        ):
            with self.subTest(response=response):
                self.fake.routes[0] = ("POST", "/chat/completions", response)
                self.assertFalse(model_health.probe("https://ai.example/v1", "spark/dsv41"))


class ModelHealthHttpTest(unittest.TestCase):
    def test_real_http_timeout_is_an_outage_and_redirects_are_not_followed(self):
        calls = []
        mode = ["healthy"]
        release = threading.Event()

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                calls.append((self.path, payload))
                if self.path.endswith("/chat/completions"):
                    if mode[0] == "redirect":
                        self.send_response(307)
                        self.send_header("Location", "/unexpected")
                        self.end_headers()
                        return
                    if mode[0] == "timeout":
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.flush()
                        release.wait(5)
                        return
                    if mode[0] == "truncated":
                        self.send_response(200)
                        self.send_header("Content-Length", "1000")
                        self.end_headers()
                        self.wfile.write(b'{"model":')
                        return
                    body = {"model": "dsv41", "choices": [{"message": {"content": "OK"}}]}
                else:
                    chat = {"id": 123456789, "type": "private"}
                    body = {"ok": True, "result": chat if self.path.endswith("/getChat") else {"chat": chat}}
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())

            def log_message(self, *_):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.addCleanup(thread.join, 2)
            self.addCleanup(server.shutdown)
            self.addCleanup(release.set)
            base = f"http://127.0.0.1:{server.server_port}"
            directory = temp_dir(self)
            env = directory / "env"
            env.write_text("TELEGRAM_BOT_TOKEN=123:fake\nTELEGRAM_ALLOWED_USERS=123456789\n")
            family = write_json(directory / "family", FAMILY)
            args = ["--env-file", str(env), "--family", str(family), "--state-dir", str(directory / "health"),
                    "--base-url", base + "/v1", "--model", "spark/dsv41"]
            with mock.patch.object(model_health, "TELEGRAM_BASE", base):
                self.assertTrue(model_health.probe(base + "/v1", "spark/dsv41"))
                self.assertEqual(calls[0][1]["model"], "spark/dsv41")
                mode[0] = "redirect"
                self.assertFalse(model_health.probe(base + "/v1", "spark/dsv41"))
                self.assertFalse(any(path == "/unexpected" for path, _ in calls))
                with mock.patch.object(model_health, "PROBE_TIMEOUT_S", 0.05):
                    for failure in ("timeout", "truncated"):
                        mode[0] = failure
                        args[5] = str(directory / failure)
                        for now in (0, 900):
                            with mock.patch.object(model_health.time, "time", return_value=now):
                                self.assertEqual(model_health.main(args), 0)
                self.assertEqual(sum(path.endswith("/sendMessage") for path, _ in calls), 2)


if __name__ == "__main__":
    unittest.main()
