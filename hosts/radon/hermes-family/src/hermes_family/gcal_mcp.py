"""gcal-mcp: the family calendar MCP server, over stdio.

`gcal-mcp proposals` offers one tool, create_proposal, which writes only to the
Proposals calendar and invites both parents. The event id is the mail key, so a
repeated run gets 409 and creates nothing. `gcal-mcp read` offers list_events
over the family calendar and, when the family file names one, the personal
calendar. Each mode gets its own credential file by argument.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Callable
from zoneinfo import ZoneInfo

from hermes_family.google import Api, Family, GoogleError, calendar_events_url, list_events, load_family
from hermes_family.state import is_key

ZONE_NAME = "Europe/Amsterdam"
ZONE = ZoneInfo(ZONE_NAME)
MAX_RANGE = timedelta(days=62)
TITLE_LIMIT = 200


def _when(value: str, *, end: bool) -> tuple[dict[str, str], date | datetime]:
    value = value.strip()
    try:
        day = date.fromisoformat(value)
    except ValueError:
        pass
    else:
        # A date-only end is the last day of the event; Google's end date is exclusive.
        stored = day + timedelta(days=1) if end else day
        return {"date": stored.isoformat()}, stored
    try:
        moment = datetime.fromisoformat(value)
    except ValueError as error:
        raise ValueError(f"not an ISO 8601 date or date-time: {value!r}") from error
    if moment.tzinfo is None:
        return {"dateTime": moment.isoformat(), "timeZone": ZONE_NAME}, moment.replace(tzinfo=ZONE)
    return {"dateTime": moment.isoformat()}, moment


def proposal_event(title: str, start: str, end: str, location: str | None, mail_key: str, family: Family) -> dict:
    if not is_key(mail_key):
        raise ValueError("mail_key must be the 32 lowercase hex characters of the Mail-Key line")
    title = " ".join(title.split())
    if not title:
        raise ValueError("title is empty")
    start_field, start_at = _when(start, end=False)
    end_field, end_at = _when(end, end=True)
    if type(start_at) is not type(end_at):
        raise ValueError("start and end must both be dates or both be date-times")
    if end_at <= start_at:
        raise ValueError("end must be after start")
    event = {
        "id": mail_key,
        "summary": title[:TITLE_LIMIT],
        "start": start_field,
        "end": end_field,
        "attendees": [{"email": parent} for parent in family.parents],
        "description": f"Proposed by Hermes from a forwarded mail (key {mail_key}). Accept to keep it.",
    }
    if location and location.strip():
        event["location"] = " ".join(location.split())[:TITLE_LIMIT]
    return event


def create_proposal(api: Api, family: Family, title: str, start: str, end: str, mail_key: str,
                    location: str | None = None) -> str:
    event = proposal_event(title, start, end, location, mail_key, family)
    response = api.call(
        "POST",
        calendar_events_url(family.proposals_calendar_id),
        params={"sendUpdates": "all"},
        body=event,
        accept=(409,),
    )
    if response.status == 409:
        return f"Proposal {mail_key} already exists; nothing to do."
    return f"Created proposal {mail_key}: {event['summary']} ({start} to {end}); both parents are invited."


def _instant(value: str) -> datetime:
    value = value.strip()
    try:
        moment = datetime.fromisoformat(value)
    except ValueError as error:
        raise ValueError(f"not an ISO 8601 date or date-time: {value!r}") from error
    return moment if moment.tzinfo else moment.replace(tzinfo=ZONE)


def _event_row(calendar: str, event: dict) -> dict:
    start, end = event.get("start") or {}, event.get("end") or {}
    row = {
        "calendar": calendar,
        "title": event.get("summary") or "(no title)",
        "start": start.get("dateTime") or start.get("date"),
        "end": end.get("dateTime") or end.get("date"),
    }
    if "date" in start:
        row["all_day"] = True
    if event.get("location"):
        row["location"] = event["location"]
    return row


def events_between(api: Api, family: Family, time_min: str, time_max: str) -> str:
    start, end = _instant(time_min), _instant(time_max)
    if end <= start:
        raise ValueError("time_max must be after time_min")
    if end - start > MAX_RANGE:
        raise ValueError(f"range is longer than {MAX_RANGE.days} days")
    calendars = [("family", family.family_calendar_id)]
    if family.personal_calendar_id:
        calendars.append(("personal", family.personal_calendar_id))
    rows, unavailable = [], []
    for label, calendar_id in calendars:
        try:
            events = list_events(api, calendar_id, start.isoformat(), end.isoformat())
        except GoogleError as error:
            if label == "family":
                raise
            unavailable.append(f"{label}: {error}")
            continue
        rows += [_event_row(label, e) for e in events if e.get("status") != "cancelled"]
    rows.sort(key=lambda row: row["start"] or "")
    result = {"time_zone": ZONE_NAME, "events": rows}
    if unavailable:
        result["unavailable"] = unavailable
    return json.dumps(result, ensure_ascii=False)


def build_server(mode: str, api_factory: Callable[[], Api], family_factory: Callable[[], Family]):
    from mcp.server.fastmcp import FastMCP

    server = FastMCP(f"gcal-{mode}")
    if mode == "proposals":

        def proposal_tool(title: str, start: str, end: str, mail_key: str, location: str | None = None) -> str:
            """Propose one event in the family's Proposals calendar and invite both parents.

            start and end are local Europe/Amsterdam ISO 8601 date-times such as
            2026-11-12T15:30:00, or dates such as 2026-11-12 for an all-day event
            (the end date is the last day). mail_key is the Mail-Key line of the
            mail, copied exactly. Running it twice for one mail key creates one event.
            """
            return create_proposal(api_factory(), family_factory(), title, start, end, mail_key, location)

        server.add_tool(proposal_tool, name="create_proposal")
    else:

        def events_tool(time_min: str, time_max: str) -> str:
            """List events between time_min and time_max (ISO 8601; a time without
            an offset is Europe/Amsterdam) from the family calendar and Joost's
            personal calendar. Read-only. At most 62 days per call.
            """
            return events_between(api_factory(), family_factory(), time_min, time_max)

        server.add_tool(events_tool, name="list_events")
    return server


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="gcal-mcp", description=__doc__.splitlines()[0])
    parser.add_argument("mode", choices=["proposals", "read"])
    parser.add_argument("--credential", type=Path, required=True,
                        help="hermes-google-proposals JSON for proposals, hermes-google-read JSON for read")
    parser.add_argument("--family", type=Path, required=True, help="hermes-family JSON")
    args = parser.parse_args(argv)
    load_family(args.family)
    build_server(
        args.mode,
        lambda: Api.from_credential_file(args.credential),
        lambda: load_family(args.family),
    ).run("stdio")
    return 0


if __name__ == "__main__":
    sys.exit(main())
