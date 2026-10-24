"""google-oauth: mint one credential for a sops key, on a laptop with a browser.

Runs Google's loopback flow for a Desktop OAuth client (PKCE, offline access,
consent prompt) with the one scope the named credential may have, and prints
the JSON the sops key holds: {client_id, client_secret, refresh_token}.
Sign in as the Hermes Google account.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import secrets
import sys
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Callable

from hermes_family import net
from hermes_family.google import TOKEN_URL

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
SCOPES = {
    "mail": "https://www.googleapis.com/auth/gmail.modify",
    "proposals": "https://www.googleapis.com/auth/calendar.events",
    "read": "https://www.googleapis.com/auth/calendar.readonly",
}
SOPS_KEYS = {"mail": "hermes-google-mail", "proposals": "hermes-google-proposals", "read": "hermes-google-read"}


class OAuthError(RuntimeError):
    pass


def load_client(path: Path) -> tuple[str, str]:
    """client_id and client_secret from a downloaded Desktop-app client JSON."""
    data = json.loads(Path(path).read_text())
    client = data.get("installed") or data
    try:
        return client["client_id"], client["client_secret"]
    except KeyError as error:
        raise OAuthError(f"{path} is not a Desktop OAuth client file: missing {error}") from error


def auth_url(client_id: str, redirect_uri: str, scope: str, state: str, challenge: str) -> str:
    return AUTH_URL + "?" + urllib.parse.urlencode(
        {
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": scope,
            "access_type": "offline",
            "prompt": "consent",
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        }
    )


def pkce_pair() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def exchange(client_id: str, client_secret: str, code: str, verifier: str, redirect_uri: str, scope: str) -> dict:
    response = net.send_form(
        TOKEN_URL,
        {
            "grant_type": "authorization_code",
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirect_uri,
        },
    )
    if not response.ok:
        raise OAuthError(f"token exchange failed: HTTP {response.status} {response.body[:300]!r}")
    token = response.json()
    if not token.get("refresh_token"):
        raise OAuthError("Google returned no refresh_token; revoke the app's access and run again")
    granted = set((token.get("scope") or "").split())
    if granted != {scope}:
        raise OAuthError(f"granted scopes {sorted(granted)} differ from the requested {scope}")
    return {"client_id": client_id, "client_secret": client_secret, "refresh_token": token["refresh_token"]}


def receive_code(open_url: Callable[[str], object], build_url: Callable[[str], str], state: str) -> tuple[str, str]:
    """Serve the loopback redirect; returns (code, redirect_uri). Requests without
    a code or an error (a favicon, a preconnect) are answered and ignored."""
    received: dict[str, str] = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            query = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(self.path).query))
            if "code" in query or "error" in query:
                received.update(query)
            ok = query.get("state") == state and "code" in query
            self.send_response(200 if ok else 400)
            self.send_header("content-type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"Done. Return to the terminal." if ok else b"Sign-in failed. Check the terminal.")

        def log_message(self, *args):
            pass

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        redirect_uri = f"http://127.0.0.1:{server.server_port}/"
        url = build_url(redirect_uri)
        print(f"Open this URL and sign in as the Hermes Google account:\n{url}", file=sys.stderr)
        open_url(url)
        while not received:
            server.handle_request()
    if received.get("state") != state:
        raise OAuthError("the redirect's state does not match; start again")
    if "code" not in received:
        raise OAuthError(f"Google returned no code: {received.get('error', 'unknown error')}")
    return received["code"], redirect_uri


def run(client_file: Path, credential: str, open_url: Callable[[str], object]) -> dict:
    client_id, client_secret = load_client(client_file)
    scope = SCOPES[credential]
    verifier, challenge = pkce_pair()
    state = secrets.token_urlsafe(24)
    code, redirect_uri = receive_code(
        open_url, lambda redirect: auth_url(client_id, redirect, scope, state, challenge), state
    )
    return exchange(client_id, client_secret, code, verifier, redirect_uri, scope)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="google-oauth", description=__doc__.splitlines()[0])
    parser.add_argument("credential", choices=sorted(SCOPES), help="which sops key: " + ", ".join(
        f"{name} -> {SOPS_KEYS[name]}" for name in sorted(SCOPES)))
    parser.add_argument("--client", type=Path, required=True, help="Desktop-app OAuth client JSON from Cloud Console")
    parser.add_argument("--no-browser", action="store_true", help="only print the URL")
    args = parser.parse_args(argv)
    try:
        result = run(args.client, args.credential, (lambda url: None) if args.no_browser else webbrowser.open)
    except OAuthError as error:
        print(f"google-oauth: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    print(f"Store the line above as sops key {SOPS_KEYS[args.credential]}.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
