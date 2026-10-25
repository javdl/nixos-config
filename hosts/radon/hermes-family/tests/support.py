"""Test seam: a stand-in for `net.send` that serves fixtures and records calls."""

from __future__ import annotations

import json
import tempfile
import unittest
import urllib.parse
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from unittest import mock

from hermes_family import net

FIXTURES = Path(__file__).parent / "fixtures"


def fixture(name: str) -> Any:
    return json.loads((FIXTURES / name).read_text())


@dataclass
class Call:
    method: str
    url: str
    params: dict[str, Any]
    body: Any

    @property
    def path(self) -> str:
        return urllib.parse.urlsplit(self.url).path


@dataclass
class FakeNet:
    """Routes are (method, url substring, responder); the first match answers.
    A responder is a JSON-able value, a (status, value) pair, or a callable
    taking the Call."""

    routes: list[tuple[str, str, Any]] = field(default_factory=list)
    calls: list[Call] = field(default_factory=list)

    def on(self, method: str, url_part: str, responder: Any) -> "FakeNet":
        self.routes.append((method, url_part, responder))
        return self

    def send(self, method, url, *, params=None, headers=None, data=None) -> net.Response:
        body = None
        if data is not None:
            content_type = (headers or {}).get("content-type", "")
            body = json.loads(data) if "json" in content_type else dict(urllib.parse.parse_qsl(data.decode()))
        call = Call(method, url, dict(params or {}), body)
        self.calls.append(call)
        for route_method, part, responder in self.routes:
            if route_method == method and part in url:
                result = responder(call) if callable(responder) else responder
                status, value = result if isinstance(result, tuple) else (200, result)
                return net.Response(status, json.dumps(value).encode())
        raise AssertionError(f"unexpected request {method} {url}")

    def patch(self, test: unittest.TestCase) -> "FakeNet":
        patcher = mock.patch.object(net, "send", self.send)
        patcher.start()
        test.addCleanup(patcher.stop)
        return self

    def matching(self, method: str, url_part: str) -> list[Call]:
        return [c for c in self.calls if c.method == method and url_part in c.url]


def temp_dir(test: unittest.TestCase) -> Path:
    directory = tempfile.TemporaryDirectory()
    test.addCleanup(directory.cleanup)
    return Path(directory.name)


def write_json(path: Path, value: Any) -> Path:
    path.write_text(json.dumps(value))
    return path


CREDENTIAL = {"client_id": "id.apps.googleusercontent.com", "client_secret": "secret", "refresh_token": "1//refresh"}
# Made up, like every value in these tests.
FAMILY = {
    "family_calendar_id": "family@group.calendar.google.com",
    "proposals_calendar_id": "proposals@group.calendar.google.com",
    "personal_calendar_id": "ouder1@example.org",
    "parents": ["ouder1@example.org", "ouder2@example.org"],
    "senders": ["groep5@school.example", "planning@opvang.example"],
    "pickup_question": "Wie haalt Kind A vandaag uit school, en wie haalt Kind B van de opvang?",
    "personal_deliver": "signal:+31600000001",
}


def token_route(fake: FakeNet) -> FakeNet:
    return fake.on("POST", "oauth2.googleapis.com/token", {"access_token": "ya29.test-token", "expires_in": 3599})


def run_document(prompt: str, response: str, job_name: str = "family-mail-parsing") -> str:
    """A run document as Hermes 81a5543 writes it (cron/scheduler.py:2638-2647,
    _run_doc_header at :2238-2246)."""
    return (
        f"# Cron Job: {job_name}\n\n**Job ID:** abc123def456\n**Run Time:** 2026-10-24 14:07:12\n"
        f"**Schedule:** */15 7-21 * * *\n\n**Prompt Characters:** {len(prompt)}\n## Prompt\n\n{prompt}\n\n"
        f"**Response Characters:** {len(response)}\n## Response\n\n{response}\n"
    )
