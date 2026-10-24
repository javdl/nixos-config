"""pickup: the 14:00 school-day question, as a no-agent cron job.

Hermes delivers stdout to the family group, and an empty stdout sends
nothing. Weekends print nothing, and so does a date whose family calendar has
a school-holiday event. If the calendar cannot be read the question is still
asked, and the error goes to the run log.
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from hermes_family.google import Api, GoogleError, list_events, load_family
from hermes_family.state import log_failure

JOB_NAME = "family-pickup"
ZONE = ZoneInfo("Europe/Amsterdam")
QUESTION = "Who picks up Floris from school today, and who picks up Mats and Julian from daycare?"
HOLIDAY_PATTERN = r"\b(\w*vakantie|studiedag|vrije dag|geen school|\w*holiday)\b"


def is_school_holiday(events: list[dict], pattern: re.Pattern[str]) -> bool:
    return any(
        event.get("status") != "cancelled" and pattern.search(event.get("summary") or "") for event in events
    )


def day_bounds(day: date) -> tuple[str, str]:
    start = datetime.combine(day, time(), ZONE)
    end = datetime.combine(day + timedelta(days=1), time(), ZONE)
    return start.isoformat(), end.isoformat()


def message(day: date, events: list[dict] | None, pattern: re.Pattern[str]) -> str:
    """The text to post for `day`; "" posts nothing. `events` None = calendar unreadable."""
    if day.weekday() >= 5:
        return ""
    if events is not None and is_school_holiday(events, pattern):
        return ""
    return QUESTION


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="pickup", description=__doc__.splitlines()[0])
    parser.add_argument("--credential", type=Path, required=True, help="hermes-google-read JSON")
    parser.add_argument("--family", type=Path, required=True, help="hermes-family JSON")
    parser.add_argument("--run-log", type=Path)
    parser.add_argument("--date", type=date.fromisoformat, help="pretend today is YYYY-MM-DD")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="the script only prints (Hermes posts its stdout), so this changes nothing; "
        "it exists for the acceptance check",
    )
    parser.add_argument("--holiday-pattern", default=HOLIDAY_PATTERN, help="regex for holiday event titles")
    args = parser.parse_args(argv)

    day = args.date or datetime.now(ZONE).date()
    pattern = re.compile(args.holiday_pattern, re.IGNORECASE)
    events = None
    if day.weekday() < 5:
        try:
            family = load_family(args.family)
            events = list_events(Api.from_credential_file(args.credential), family.family_calendar_id, *day_bounds(day))
        except (GoogleError, OSError) as error:
            log_failure(args.run_log, JOB_NAME, f"family calendar unreadable, asked anyway: {error}")
    text = message(day, events, pattern)
    if text:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
