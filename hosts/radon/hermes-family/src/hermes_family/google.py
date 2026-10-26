"""Google OAuth credentials, the family file, and the Gmail and Calendar calls
the jobs use. Every request goes through `net.send`."""

from __future__ import annotations

import base64
import json
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from hermes_family import net

TOKEN_URL = "https://oauth2.googleapis.com/token"
GMAIL = "https://gmail.googleapis.com/gmail/v1/users/me"
CALENDAR = "https://www.googleapis.com/calendar/v3"


class GoogleError(RuntimeError):
    pass


@dataclass(frozen=True)
class Credential:
    client_id: str
    client_secret: str
    refresh_token: str


@dataclass(frozen=True)
class Family:
    family_calendar_id: str
    proposals_calendar_id: str
    personal_calendar_id: str | None
    parents: tuple[str, str]
    pickup_question: str | None


def _load_object(path: Path, what: str) -> dict[str, Any]:
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise GoogleError(f"cannot read {what} {path}: {error}") from error
    if not isinstance(data, dict):
        raise GoogleError(f"{what} {path} is not a JSON object")
    return data


def _text(data: dict[str, Any], key: str, what: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise GoogleError(f"{what} lacks a non-empty string {key!r}")
    return value.strip()


def _optional_text(data: dict[str, Any], key: str) -> str | None:
    value = data.get(key)
    return value.strip() if isinstance(value, str) and value.strip() else None


def load_credential(path: Path) -> Credential:
    data = _load_object(path, "credential")
    return Credential(*(_text(data, key, "credential") for key in ("client_id", "client_secret", "refresh_token")))


def load_family(path: Path) -> Family:
    data = _load_object(path, "family file")
    parents = data.get("parents")
    if (
        not isinstance(parents, list)
        or len(parents) != 2
        or not all(isinstance(p, str) and "@" in p for p in parents)
    ):
        raise GoogleError("family file needs parents: [email, email]")
    return Family(
        family_calendar_id=_text(data, "family_calendar_id", "family file"),
        proposals_calendar_id=_text(data, "proposals_calendar_id", "family file"),
        personal_calendar_id=_optional_text(data, "personal_calendar_id"),
        parents=(parents[0].strip(), parents[1].strip()),
        pickup_question=_optional_text(data, "pickup_question"),
    )


def access_token(credential: Credential) -> str:
    response = net.send_form(
        TOKEN_URL,
        {
            "grant_type": "refresh_token",
            "client_id": credential.client_id,
            "client_secret": credential.client_secret,
            "refresh_token": credential.refresh_token,
        },
    )
    if not response.ok:
        raise GoogleError(f"token refresh failed: HTTP {response.status} {response.body[:200]!r}")
    token = response.json().get("access_token")
    if not token:
        raise GoogleError("token refresh returned no access_token")
    return token


class Api:
    """Authorized JSON calls with one access token."""

    def __init__(self, token: str):
        self._auth = {"authorization": f"Bearer {token}"}

    @classmethod
    def from_credential_file(cls, path: Path) -> "Api":
        return cls(access_token(load_credential(path)))

    def call(self, method: str, url: str, *, params=None, body=None, accept=()) -> net.Response:
        if body is None:
            response = net.send(method, url, params=params, headers=self._auth)
        else:
            response = net.send_json(method, url, body, params=params, headers=self._auth)
        if not response.ok and response.status not in accept:
            raise GoogleError(f"{method} {url.split('?')[0]}: HTTP {response.status} {response.body[:300]!r}")
        return response


class Gmail:
    def __init__(self, api: Api):
        self.api = api

    def message_ids(self, query: str, limit: int) -> list[str]:
        """Matching message ids, oldest first, at most `limit`."""
        ids: list[str] = []
        page = None
        while True:
            params = {"q": query, "maxResults": 100}
            if page:
                params["pageToken"] = page
            data = self.api.call("GET", f"{GMAIL}/messages", params=params).json()
            ids += [m["id"] for m in data.get("messages") or []]
            page = data.get("nextPageToken")
            if not page:
                break
        return list(reversed(ids))[:limit]

    def message(self, message_id: str) -> dict[str, Any]:
        return self.api.call("GET", f"{GMAIL}/messages/{message_id}", params={"format": "full"}).json()

    def attachment(self, message_id: str, attachment_id: str) -> str:
        """The base64url data of a part body Gmail stores as an attachment."""
        url = f"{GMAIL}/messages/{message_id}/attachments/{attachment_id}"
        return self.api.call("GET", url).json().get("data") or ""

    def label_id(self, name: str) -> str:
        """The id of a user label, created when missing."""
        labels = self.api.call("GET", f"{GMAIL}/labels").json().get("labels") or []
        for label in labels:
            if label.get("name") == name:
                return label["id"]
        created = self.api.call(
            "POST",
            f"{GMAIL}/labels",
            body={"name": name, "labelListVisibility": "labelShow", "messageListVisibility": "show"},
        )
        return created.json()["id"]

    def add_label(self, message_id: str, label_id: str) -> None:
        self.api.call("POST", f"{GMAIL}/messages/{message_id}/modify", body={"addLabelIds": [label_id]})


def calendar_events_url(calendar_id: str) -> str:
    return f"{CALENDAR}/calendars/{urllib.parse.quote(calendar_id, safe='')}/events"


def list_events(api: Api, calendar_id: str, time_min: str, time_max: str) -> list[dict[str, Any]]:
    """Single events (recurrences expanded) overlapping [time_min, time_max)."""
    events: list[dict[str, Any]] = []
    page = None
    while True:
        params = {
            "timeMin": time_min,
            "timeMax": time_max,
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": 250,
        }
        if page:
            params["pageToken"] = page
        data = api.call("GET", calendar_events_url(calendar_id), params=params).json()
        events += data.get("items") or []
        page = data.get("nextPageToken")
        if not page:
            return events


def decode_body(data: str) -> str:
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4)).decode("utf-8", errors="replace")
