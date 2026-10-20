"""Probe behaviour without the network, launchd, or radon's disk."""

import importlib.util
import json
import tempfile
import threading
import unittest
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def load_probe():
    path = Path(__file__).resolve().parents[1] / "scripts" / "radon-fleet-health.py"
    spec = importlib.util.spec_from_file_location("radon_fleet_health", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


probe = load_probe()


class CurlContractTests(unittest.TestCase):
    def test_argv_is_short_unauthenticated_and_discards_the_body(self):
        argv = probe.curl_argv("/usr/bin/curl", "https://ai.buri-hoki.ts.net/v1/models")
        self.assertEqual(argv[0], "/usr/bin/curl")
        self.assertIn("-q", argv)
        self.assertIn("--output", argv)
        self.assertEqual(argv[argv.index("--output") + 1], "/dev/null")
        self.assertEqual(argv[argv.index("--connect-timeout") + 1], "3")
        self.assertEqual(argv[argv.index("--max-time") + 1], "5")
        for forbidden in ("-H", "--header", "--user", "-u", "-k", "--insecure"):
            self.assertNotIn(forbidden, argv)
        self.assertNotIn("stargazer-duck", argv[-1])
        self.assertNotIn("Authorization", " ".join(argv))

    def test_pair_body_capture_stays_unauthenticated(self):
        argv = probe.curl_argv(
            "/usr/bin/curl",
            "http://j9.buri-hoki.ts.net:11434/v1/models",
            capture_body=True,
        )
        self.assertEqual(argv[argv.index("--output") + 1], "-")
        self.assertEqual(argv[argv.index("--write-out") + 1], "\n%{http_code}")
        for forbidden in ("-H", "--header", "--user", "-u", "-k", "--insecure", "--fail"):
            self.assertNotIn(forbidden, argv)
        self.assertNotIn("Authorization", " ".join(argv))

    def test_remote_pair_checks_read_the_body_and_radon_does_not(self):
        by_name = {item["name"]: item for item in probe.HTTP_CHECKS}
        for name in ("spark_ollama", "spark2_ollama", "j9_ollama"):
            self.assertTrue(by_name[name].get("pair_proxy"))
            self.assertTrue(by_name[name]["url"].endswith(":11434/v1/models"))
            self.assertNotIn("127.0.0.1", by_name[name]["url"])
        self.assertNotIn("pair_proxy", by_name["radon_ollama"])
        self.assertEqual(by_name["radon_ollama"]["url"], "http://127.0.0.1:11434/v1/models")
        self.assertNotIn("pair_proxy", by_name["spark_vllm"])
        self.assertNotIn("pair_proxy", by_name["aperture"])

    def test_targets_stay_on_the_personal_tailnet_or_loopback(self):
        urls = [item["url"] for item in probe.HTTP_CHECKS]
        self.assertIn("http://spark.buri-hoki.ts.net:11434/v1/models", urls)
        self.assertIn("https://spark.buri-hoki.ts.net:8443/health", urls)
        self.assertIn("http://spark2.buri-hoki.ts.net:11434/v1/models", urls)
        self.assertIn("http://j9.buri-hoki.ts.net:11434/v1/models", urls)
        self.assertIn("http://127.0.0.1:8787/", urls)
        self.assertIn("http://127.0.0.1:11434/v1/models", urls)
        self.assertIn("https://ai.buri-hoki.ts.net/v1/models", urls)
        for url in urls:
            self.assertNotIn("stargazer-duck", url)
            self.assertNotIn("bali", url)


class HttpInterpretationTests(unittest.TestCase):
    def test_ollama_200_is_ok_and_keeps_no_body(self):
        result = probe.interpret_http("http_2xx", 0, "200", "", 12)
        self.assertEqual(result, {"ok": True, "status": 200, "latency": 12, "error": None})

    def test_aperture_records_status_without_requiring_200(self):
        result = probe.interpret_http("http_any", 0, "401", "", 40)
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"], 401)
        self.assertIsNone(result["error"])

    def test_non_2xx_ollama_is_not_ok(self):
        result = probe.interpret_http("http_2xx", 0, "500", "", 9)
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 500)
        self.assertEqual(result["error"], "HTTP 500")

    def test_curl_failure_has_no_status(self):
        result = probe.interpret_http("http_2xx", 7, "000", "curl: (7) Failed to connect\n", 3)
        self.assertFalse(result["ok"])
        self.assertIsNone(result["status"])
        self.assertIn("Failed to connect", result["error"])

    def test_pair_loopback_403_is_up(self):
        body = (
            '{"code":"loopback-only","error":"plaintext requests are accepted only from '
            'loopback; cluster peers must use the mTLS ingress"}'
        )
        self.assertTrue(probe.pair_loopback_only(body))
        result = probe.interpret_http("http_2xx", 0, "403", "", 18, body=body, pair_proxy=True)
        self.assertEqual(
            result,
            {
                "ok": True,
                "status": 403,
                "latency": 18,
                "error": None,
                "detail": "up (PAIR proxy, loopback-only for plaintext)",
            },
        )
        huge = '{"code":"loopback-only","pad":"' + ("x" * probe.PAIR_BODY_LIMIT) + '"}'
        self.assertFalse(probe.pair_loopback_only(huge))

    def test_pair_body_and_status_split_keeps_the_code_line(self):
        body = '{"code":"loopback-only","error":"plaintext requests are accepted only from loopback"}\n'
        raw = body + "403"
        parsed_body, code = probe.split_status_and_body(raw)
        self.assertEqual(code, "403")
        self.assertTrue(probe.pair_loopback_only(parsed_body))

    def test_other_403_stays_a_failure(self):
        for body in (
            '{"code":"denied","error":"no"}',
            '{"error":"loopback-only"}',
            "<html>403 forbidden</html>",
            "",
            "not json",
        ):
            result = probe.interpret_http("http_2xx", 0, "403", "", 8, body=body, pair_proxy=True)
            self.assertFalse(result["ok"], body)
            self.assertEqual(result["status"], 403)
            self.assertEqual(result["error"], "HTTP 403")
            self.assertNotIn("detail", result)

    def test_radon_loopback_403_stays_a_failure(self):
        body = '{"code":"loopback-only","error":"plaintext requests are accepted only from loopback"}'
        result = probe.interpret_http("http_2xx", 0, "403", "", 4, body=body, pair_proxy=False)
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 403)
        self.assertEqual(result["error"], "HTTP 403")
        self.assertNotIn("detail", result)

    def test_pair_timeout_and_connect_failure_stay_failures(self):
        timed_out = probe.interpret_http(
            "http_2xx",
            28,
            "000",
            "curl: (28) Connection timed out after 5000 milliseconds",
            5000,
            body="",
            pair_proxy=True,
        )
        self.assertFalse(timed_out["ok"])
        self.assertIsNone(timed_out["status"])
        self.assertIn("timed out", timed_out["error"])
        self.assertNotIn("detail", timed_out)
        refused = probe.interpret_http(
            "http_2xx",
            7,
            "000",
            "curl: (7) Failed to connect to j9 port 11434: Connection refused",
            12,
            body="",
            pair_proxy=True,
        )
        self.assertFalse(refused["ok"])
        self.assertIsNone(refused["status"])
        self.assertIn("Connection refused", refused["error"])


class PolicyTests(unittest.TestCase):
    def test_timeout_while_ollama_answered_is_policy(self):
        vllm = probe.interpret_http(
            "http_2xx",
            28,
            "000",
            "curl: (28) Connection timed out after 5000 milliseconds",
            5000,
        )
        ollama = probe.interpret_http("http_2xx", 0, "200", "", 20)
        classified = probe.classify_vllm(vllm, ollama)
        self.assertFalse(classified["ok"])
        self.assertIsNone(classified["status"])
        self.assertEqual(classified["error"], "not reachable by policy")
        self.assertIn("timed out", classified["detail"])

    def test_timeout_while_spark_is_down_is_not_called_policy(self):
        vllm = probe.interpret_http("http_2xx", 28, "000", "curl: (28) Connection timed out", 5000)
        ollama = probe.interpret_http("http_2xx", 28, "000", "curl: (28) Connection timed out", 5000)
        classified = probe.classify_vllm(vllm, ollama)
        self.assertNotEqual(classified["error"], "not reachable by policy")

    def test_connection_refused_is_not_called_policy(self):
        vllm = probe.interpret_http(
            "http_2xx",
            7,
            "000",
            "curl: (7) Failed to connect to spark port 8443: Connection refused",
            15,
        )
        ollama = probe.interpret_http("http_2xx", 0, "200", "", 20)
        classified = probe.classify_vllm(vllm, ollama)
        self.assertNotEqual(classified["error"], "not reachable by policy")
        self.assertIn("Connection refused", classified["error"])

    def test_pair_403_still_counts_as_spark_answered(self):
        vllm = probe.interpret_http("http_2xx", 28, "000", "curl: (28) Connection timed out", 5000)
        body = '{"code":"loopback-only","error":"plaintext requests are accepted only from loopback"}'
        ollama = probe.interpret_http("http_2xx", 0, "403", "", 20, body=body, pair_proxy=True)
        classified = probe.classify_vllm(vllm, ollama)
        self.assertEqual(classified["error"], "not reachable by policy")

    def test_http_status_means_the_port_was_allowed(self):
        vllm = probe.interpret_http("http_2xx", 0, "200", "", 30)
        ollama = probe.interpret_http("http_2xx", 0, "200", "", 20)
        classified = probe.classify_vllm(vllm, ollama)
        self.assertTrue(classified["ok"])
        self.assertEqual(classified["status"], 200)
        self.assertNotIn("detail", classified)


class LocalCheckTests(unittest.TestCase):
    def test_agent_volume_mount_line(self):
        mounted = "/dev/disk4s1 on /Volumes/Agent (apfs, local, nodev)\n"
        result = probe.agent_volume_check(mounted, "/Volumes/Agent", 1)
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"], "mounted")
        absent = probe.agent_volume_check("/dev/disk1 on / (apfs)\n", "/Volumes/Agent", 1)
        self.assertFalse(absent["ok"])
        self.assertEqual(absent["status"], "absent")

    def test_df_parser_uses_posix_available_column(self):
        text = "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk1 100 20 80 20% /\n"
        self.assertEqual(probe.parse_df(text, "/"), 80 * 1024)
        result = probe.disk_check(text, "/", 2)
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"], 80 * 1024)
        self.assertEqual(result["free_bytes"], 80 * 1024)
        self.assertIsNone(result["error"])

    def test_auto_update_keeps_last_line_and_exit(self):
        log = "building\nerror: flake failed\n"
        launchctl = "state = running\nlast exit code = 1\n"
        result = probe.auto_update_check(log, None, launchctl, 4)
        self.assertEqual(result["last_line"], "error: flake failed")
        self.assertEqual(result["exit"], 1)
        self.assertFalse(result["ok"])

    def test_auto_update_unreadable_does_not_invent_an_exit(self):
        result = probe.auto_update_check(None, "log not readable", "Could not find service in domain\n", 1)
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "log not readable")
        self.assertIsNone(result["exit"])
        self.assertIsNone(result["last_line"])

    def test_successful_log_without_a_visible_exit(self):
        result = probe.auto_update_check("switching profile\nactivation finished\n", None, "", 3)
        self.assertTrue(result["ok"])
        self.assertEqual(result["last_line"], "activation finished")
        self.assertIsNone(result["exit"])


class PublishTests(unittest.TestCase):
    def test_latest_history_and_retention(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)
            payload = probe.collect(
                {
                    "spark_ollama": probe.check(True, 200, 10, None),
                    "spark_vllm": probe.interpret_http("http_2xx", 28, "000", "curl: (28) Connection timed out", 5000),
                    "spark2_ollama": probe.check(True, 200, 11, None),
                    "j9_ollama": probe.check(True, 200, 12, None),
                    "radon_hermes_webui": probe.check(True, 200, 5, None),
                    "radon_ollama": probe.check(True, 200, 6, None),
                    "aperture": probe.check(True, 401, 40, None),
                },
                {
                    "agent_volume": probe.check(True, "mounted", 1, None),
                    "auto_update": probe.auto_update_check("done\n", None, "last exit code = 0\n", 2),
                    "disk": probe.check(True, 99, 1, None),
                },
                "2026-10-16T00:00:00Z",
            )
            self.assertEqual(payload["checks"]["spark_vllm"]["error"], "not reachable by policy")
            self.assertEqual(payload["checks"]["aperture"]["status"], 401)
            history = state / "history"
            history.mkdir()
            (history / "2026-10-01.jsonl").write_text("{}\n")
            (history / "2026-10-03.jsonl").write_text("{}\n")
            latest = probe.publish(payload, state, date(2026, 10, 16), 14)
            written = json.loads(latest.read_text())
            self.assertEqual(written["host"], "radon")
            self.assertEqual(written["timestamp"], "2026-10-16T00:00:00Z")
            self.assertEqual(oct(latest.stat().st_mode & 0o777), "0o600")
            self.assertFalse((history / "2026-10-01.jsonl").exists())
            self.assertTrue((history / "2026-10-03.jsonl").exists())
            day = (history / "2026-10-16.jsonl").read_text().strip()
            self.assertEqual(json.loads(day)["checks"]["spark_vllm"]["error"], "not reachable by policy")
            self.assertNotIn("sk-", latest.read_text())

    def test_second_lock_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)
            first = probe.exclusive_lock(state)
            self.assertIsNotNone(first)
            second = probe.exclusive_lock(state)
            self.assertIsNone(second)
            first.close()
            second = probe.exclusive_lock(state)
            self.assertIsNotNone(second)
            second.close()

    def test_refuses_root_and_hermes_and_skips_other_users(self):
        self.assertEqual(probe.gate_user("root", "joost"), 1)
        self.assertEqual(probe.gate_user("hermes", "joost"), 1)
        self.assertEqual(probe.gate_user("nobody", "joost"), 0)
        self.assertIsNone(probe.gate_user("joost", "joost"))


LIVE_PAIR_BODY = (
    '{"code":"loopback-only","error":"plaintext requests are accepted only from '
    'loopback; cluster peers must use the mTLS ingress"}'
)


class _PairHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/denied"):
            body = b'{"code":"denied"}'
            status = 403
        elif self.path.startswith("/ok"):
            body = b'{"models":[]}'
            status = 200
        else:
            body = LIVE_PAIR_BODY.encode()
            status = 403
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


class LocalCurlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), _PairHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.server.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def _probes(self):
        return probe.RealProbes("/usr/bin/curl", "/Volumes/Agent", Path("/tmp/radon-fleet-health-missing.log"))

    def test_real_curl_counts_loopback_only_and_leaves_radon_unchanged(self):
        probes = self._probes()
        remote = probes.http(
            {
                "name": "j9_ollama",
                "url": f"http://127.0.0.1:{self.port}/v1/models",
                "kind": "http_2xx",
                "pair_proxy": True,
            }
        )
        local = probes.http(
            {
                "name": "radon_ollama",
                "url": f"http://127.0.0.1:{self.port}/v1/models",
                "kind": "http_2xx",
            }
        )
        self.assertEqual(remote["status"], 403)
        self.assertTrue(remote["ok"])
        self.assertIsNone(remote["error"])
        self.assertEqual(remote["detail"], probe.PAIR_LOOPBACK_DETAIL)
        self.assertNotIn("plaintext requests", json.dumps(remote))
        self.assertFalse(local["ok"])
        self.assertEqual(local["status"], 403)
        self.assertEqual(local["error"], "HTTP 403")
        self.assertNotIn("detail", local)

    def test_real_curl_other_403_and_200(self):
        probes = self._probes()
        denied = probes.http(
            {
                "name": "spark_ollama",
                "url": f"http://127.0.0.1:{self.port}/denied",
                "kind": "http_2xx",
                "pair_proxy": True,
            }
        )
        healthy = probes.http(
            {
                "name": "spark2_ollama",
                "url": f"http://127.0.0.1:{self.port}/ok",
                "kind": "http_2xx",
                "pair_proxy": True,
            }
        )
        self.assertFalse(denied["ok"])
        self.assertEqual(denied["error"], "HTTP 403")
        self.assertNotIn("detail", denied)
        self.assertEqual(
            healthy,
            {"ok": True, "status": 200, "latency": healthy["latency"], "error": None, "target": healthy["target"]},
        )

    def test_real_curl_connect_failure_stays_a_failure(self):
        probes = self._probes()
        result = probes.http(
            {
                "name": "j9_ollama",
                "url": "http://127.0.0.1:1/v1/models",
                "kind": "http_2xx",
                "pair_proxy": True,
            }
        )
        self.assertFalse(result["ok"])
        self.assertIsNone(result["status"])
        self.assertNotIn("detail", result)


if __name__ == "__main__":
    unittest.main()
