"""Probe behaviour without the network, launchd, or radon's disk."""

import importlib.util
import json
import tempfile
import unittest
from datetime import date
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


if __name__ == "__main__":
    unittest.main()
