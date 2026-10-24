import base64
import hashlib
import io
import json
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from contextlib import redirect_stderr, redirect_stdout

from hermes_family import oauth
from tests.support import FakeNet, temp_dir, write_json

DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))
CLIENT = {"installed": {"client_id": "desk.apps.googleusercontent.com", "client_secret": "desk-secret",
                        "redirect_uris": ["http://localhost"]}}


def browser_that_consents(code: str = "4/code", tamper_state: bool = False, favicon_first: bool = False):
    """Plays Google: reads the auth URL and hits the loopback redirect."""
    seen = {}

    def open_url(url: str) -> None:
        query = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query))
        seen.update(query)
        state = "forged" if tamper_state else query["state"]
        redirect = query["redirect_uri"]

        def hit():
            if favicon_first:
                try:
                    DIRECT.open(redirect + "favicon.ico", timeout=5)
                except urllib.error.HTTPError:
                    pass
            try:
                DIRECT.open(f"{redirect}?{urllib.parse.urlencode({'state': state, 'code': code})}", timeout=5)
            except urllib.error.HTTPError:
                pass

        threading.Thread(target=hit, daemon=True).start()

    return open_url, seen


class OAuthTest(unittest.TestCase):
    def setUp(self):
        self.client = write_json(temp_dir(self) / "client.json", CLIENT)

    def token_fake(self, scope: str, refresh: str | None = "1//refresh") -> FakeNet:
        body = {"access_token": "ya29.x", "expires_in": 3599, "scope": scope, "token_type": "Bearer"}
        if refresh:
            body["refresh_token"] = refresh
        return FakeNet().on("POST", "oauth2.googleapis.com/token", body).patch(self)

    def test_loopback_flow_prints_the_sops_json(self):
        fake = self.token_fake(oauth.SCOPES["mail"])
        open_url, seen = browser_that_consents(favicon_first=True)
        with redirect_stderr(io.StringIO()):
            result = oauth.run(self.client, "mail", open_url)
        self.assertEqual(result, {"client_id": "desk.apps.googleusercontent.com", "client_secret": "desk-secret",
                                  "refresh_token": "1//refresh"})
        self.assertEqual(seen["scope"], "https://www.googleapis.com/auth/gmail.modify")
        self.assertEqual((seen["access_type"], seen["prompt"], seen["code_challenge_method"]), ("offline", "consent", "S256"))
        self.assertTrue(seen["redirect_uri"].startswith("http://127.0.0.1:"))
        exchange = fake.calls[0].body
        self.assertEqual((exchange["grant_type"], exchange["code"]), ("authorization_code", "4/code"))
        self.assertEqual(exchange["redirect_uri"], seen["redirect_uri"])
        challenge = base64.urlsafe_b64encode(hashlib.sha256(exchange["code_verifier"].encode()).digest()).rstrip(b"=")
        self.assertEqual(challenge.decode(), seen["code_challenge"])

    def test_each_credential_asks_for_exactly_its_scope(self):
        self.assertEqual(oauth.SCOPES, {
            "mail": "https://www.googleapis.com/auth/gmail.modify",
            "proposals": "https://www.googleapis.com/auth/calendar.events",
            "read": "https://www.googleapis.com/auth/calendar.readonly",
        })

    def test_state_mismatch_is_refused(self):
        self.token_fake(oauth.SCOPES["read"])
        open_url, _ = browser_that_consents(tamper_state=True)
        with redirect_stderr(io.StringIO()), self.assertRaises(oauth.OAuthError):
            oauth.run(self.client, "read", open_url)

    def test_wider_grant_is_refused(self):
        self.token_fake(oauth.SCOPES["read"] + " https://www.googleapis.com/auth/calendar")
        open_url, _ = browser_that_consents()
        with redirect_stderr(io.StringIO()), self.assertRaises(oauth.OAuthError):
            oauth.run(self.client, "read", open_url)

    def test_missing_refresh_token_is_refused(self):
        self.token_fake(oauth.SCOPES["proposals"], refresh=None)
        open_url, _ = browser_that_consents()
        with redirect_stderr(io.StringIO()), self.assertRaises(oauth.OAuthError) as caught:
            oauth.run(self.client, "proposals", open_url)
        self.assertIn("refresh_token", str(caught.exception))

    def test_main_prints_one_json_line(self):
        self.token_fake(oauth.SCOPES["proposals"])
        open_url, _ = browser_that_consents()
        out = io.StringIO()
        oauth_open = oauth.webbrowser.open
        oauth.webbrowser.open = open_url
        self.addCleanup(setattr, oauth.webbrowser, "open", oauth_open)
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            self.assertEqual(oauth.main(["proposals", "--client", str(self.client)]), 0)
        self.assertEqual(json.loads(out.getvalue())["refresh_token"], "1//refresh")


if __name__ == "__main__":
    unittest.main()
