"""plan-ahead-weather: the Friday plan-ahead job's --script.

Prints a compact block that Hermes injects into the job's prompt: the
weekend's weather and wind at the Zandvoort and Bloemendaal aan Zee beaches
(Open-Meteo, no key) and the astronomical tide times at IJmuiden buitenhaven
(Rijkswaterstaat Waterwebservices, no key), the nearest tide station to both
beaches. A source that fails becomes one "unavailable" line.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from hermes_family import net

ZONE_NAME = "Europe/Amsterdam"
ZONE = ZoneInfo(ZONE_NAME)
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
TIDE_URL = "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES/OphalenWaarnemingen"
TIDE_STATION = "ijmuiden.buitenhaven"
DAILY = (
    "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,"
    "sunshine_duration,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant"
)


@dataclass(frozen=True)
class Place:
    name: str
    latitude: float
    longitude: float


PLACES = (Place("Zandvoort", 52.373, 4.525), Place("Bloemendaal aan Zee", 52.410, 4.555))

WMO = {
    0: "clear", 1: "mostly clear", 2: "partly cloudy", 3: "overcast", 45: "fog", 48: "freezing fog",
    51: "light drizzle", 53: "drizzle", 55: "heavy drizzle", 56: "freezing drizzle", 57: "freezing drizzle",
    61: "light rain", 63: "rain", 65: "heavy rain", 66: "freezing rain", 67: "freezing rain",
    71: "light snow", 73: "snow", 75: "heavy snow", 77: "snow grains", 80: "light showers",
    81: "showers", 82: "heavy showers", 85: "snow showers", 86: "heavy snow showers",
    95: "thunderstorm", 96: "thunderstorm with hail", 99: "thunderstorm with hail",
}
BEAUFORT_KMH = (1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118)
COMPASS = ("N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW")


def weekend(today: date) -> tuple[date, date]:
    saturday = today + timedelta(days=(5 - today.weekday()) % 7)
    return saturday, saturday + timedelta(days=1)


def beaufort(kmh: float) -> int:
    return next((force for force, limit in enumerate(BEAUFORT_KMH) if kmh < limit), 12)


def compass(degrees: float) -> str:
    return COMPASS[round(degrees / 22.5) % 16]


def forecast(start: date, end: date) -> list[dict]:
    response = net.send(
        "GET",
        FORECAST_URL,
        params={
            "latitude": ",".join(str(p.latitude) for p in PLACES),
            "longitude": ",".join(str(p.longitude) for p in PLACES),
            "daily": DAILY,
            "timezone": ZONE_NAME,
            "wind_speed_unit": "kmh",
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
        },
    )
    if not response.ok:
        raise RuntimeError(f"Open-Meteo HTTP {response.status}")
    data = response.json()
    return data if isinstance(data, list) else [data]


def day_line(place: Place, daily: dict, index: int) -> str:
    def value(key):
        return daily[key][index]

    sky = WMO.get(value("weather_code"), f"weather code {value('weather_code')}")
    wind = value("wind_speed_10m_max")
    return (
        f"  {place.name}: {sky}, {value('temperature_2m_min'):.0f} to {value('temperature_2m_max'):.0f} °C, "
        f"rain {value('precipitation_sum'):.1f} mm ({value('precipitation_probability_max')}% chance), "
        f"sun {value('sunshine_duration') / 3600:.1f} h, "
        f"wind {compass(value('wind_direction_10m_dominant'))} {beaufort(wind)} Bft ({wind:.0f} km/h), "
        f"gusts {value('wind_gusts_10m_max'):.0f} km/h"
    )


def tides(start: date, end: date) -> list[tuple[datetime, int]]:
    begin = datetime.combine(start, datetime.min.time(), ZONE)
    finish = datetime.combine(end + timedelta(days=1), datetime.min.time(), ZONE)
    response = net.send_json(
        "POST",
        TIDE_URL,
        {
            "Locatie": {"Code": TIDE_STATION},
            "AquoPlusWaarnemingMetadata": {
                "AquoMetadata": {
                    "Grootheid": {"Code": "WATHTE"},
                    "Groepering": {"Code": "GETETBRKD2"},
                    "ProcesType": "astronomisch",
                }
            },
            "Periode": {
                "Begindatumtijd": begin.isoformat(timespec="milliseconds"),
                "Einddatumtijd": finish.isoformat(timespec="milliseconds"),
            },
        },
    )
    if not response.ok:
        raise RuntimeError(f"Rijkswaterstaat HTTP {response.status}")
    data = response.json()
    if not data.get("Succesvol"):
        raise RuntimeError(f"Rijkswaterstaat: {data.get('Foutmelding') or 'no data'}")
    points = [
        (datetime.fromisoformat(m["Tijdstip"]).astimezone(ZONE), round(m["Meetwaarde"]["Waarde_Numeriek"]))
        for series in data.get("WaarnemingenLijst") or []
        for m in series.get("MetingenLijst") or []
    ]
    return sorted(points)


def tide_lines(points: list[tuple[datetime, int]], days: tuple[date, date]) -> list[str]:
    """Extremes alternate, so an extreme above its neighbours is high water."""
    lines = []
    for day in days:
        parts = []
        for index, (moment, level) in enumerate(points):
            if moment.date() != day:
                continue
            neighbours = [points[i][1] for i in (index - 1, index + 1) if 0 <= i < len(points)]
            kind = "high" if all(level > other for other in neighbours) else "low"
            parts.append(f"{kind} {moment:%H:%M} ({level:+d} cm NAP)")
        lines.append(f"  {day:%a %Y-%m-%d}: {', '.join(parts) if parts else 'no data'}")
    return lines


def report(today: date) -> str:
    saturday, sunday = weekend(today)
    lines = [f"Weekend weather, Open-Meteo forecast ({ZONE_NAME}):"]
    try:
        series = forecast(saturday, sunday)
        for index, day in enumerate((saturday, sunday)):
            lines.append(f"{day:%a %Y-%m-%d}")
            lines += [day_line(place, data["daily"], index) for place, data in zip(PLACES, series, strict=True)]
    except (RuntimeError, OSError, KeyError, IndexError, TypeError, ValueError) as error:
        lines.append(f"  unavailable: {error}")
    lines.append("Tide times, IJmuiden buitenhaven, the nearest tide station (Rijkswaterstaat, astronomical):")
    try:
        lines += tide_lines(tides(saturday, sunday), (saturday, sunday))
    except (RuntimeError, OSError, KeyError, TypeError, ValueError) as error:
        lines.append(f"  unavailable: {error}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="plan-ahead-weather", description=__doc__.splitlines()[0])
    parser.add_argument("--today", type=date.fromisoformat, help="pretend today is YYYY-MM-DD")
    args = parser.parse_args(argv)
    print(report(args.today or datetime.now(ZONE).date()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
