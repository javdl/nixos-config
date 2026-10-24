"""The one HTTP seam. Every Google, Open-Meteo and Rijkswaterstaat call goes
through `send`, and the tests replace it with recorded fixtures."""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any

TIMEOUT_S = 30


@dataclass(frozen=True)
class Response:
    status: int
    body: bytes

    @property
    def ok(self) -> bool:
        return 200 <= self.status < 300

    def json(self) -> Any:
        return json.loads(self.body or b"null")


def send(
    method: str,
    url: str,
    *,
    params: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    data: bytes | None = None,
) -> Response:
    """An HTTP error status is a Response, not an exception. Only transport
    failures (DNS, refused, timeout) raise."""
    if params:
        url = f"{url}?{urllib.parse.urlencode(params, doseq=True)}"
    request = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            return Response(response.status, response.read())
    except urllib.error.HTTPError as error:
        return Response(error.code, error.read())


def send_json(method: str, url: str, body: Any, *, params=None, headers=None) -> Response:
    return send(
        method,
        url,
        params=params,
        headers={"content-type": "application/json", **(headers or {})},
        data=json.dumps(body).encode(),
    )


def send_form(url: str, fields: dict[str, str]) -> Response:
    return send(
        "POST",
        url,
        headers={"content-type": "application/x-www-form-urlencoded"},
        data=urllib.parse.urlencode(fields).encode(),
    )
