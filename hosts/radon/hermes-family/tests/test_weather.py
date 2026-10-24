import unittest
from datetime import date

from hermes_family import weather
from tests.support import FakeNet, fixture

FORECAST = fixture("open-meteo-2026-10-31.json")
TIDE = fixture("rws-tide-2026-10-31.json")


class WeatherTest(unittest.TestCase):
    def report(self, fake: FakeNet, today: date = date(2026, 10, 30)) -> str:
        fake.patch(self)
        return weather.report(today)

    def test_friday_report_covers_both_beaches_and_tides(self):
        fake = FakeNet().on("GET", "api.open-meteo.com", FORECAST).on("POST", "rijkswaterstaat.nl", TIDE)
        self.assertEqual(
            self.report(fake),
            "Weekend weather, Open-Meteo forecast (Europe/Amsterdam):\n"
            "Sat 2026-10-31\n"
            "  Zandvoort: fog, 8 to 12 °C, rain 0.0 mm (12% chance), sun 8.0 h, wind ENE 3 Bft (13 km/h), gusts 20 km/h\n"
            "  Bloemendaal aan Zee: fog, 8 to 12 °C, rain 0.0 mm (12% chance), sun 8.0 h, wind ENE 3 Bft (13 km/h), gusts 20 km/h\n"
            "Sun 2026-11-01\n"
            "  Zandvoort: overcast, 8 to 11 °C, rain 0.0 mm (10% chance), sun 3.6 h, wind NNE 2 Bft (12 km/h), gusts 21 km/h\n"
            "  Bloemendaal aan Zee: overcast, 8 to 11 °C, rain 0.0 mm (10% chance), sun 3.6 h, wind NNE 2 Bft (12 km/h), gusts 21 km/h\n"
            "Tide times, IJmuiden buitenhaven, the nearest tide station (Rijkswaterstaat, astronomical):\n"
            "  Sat 2026-10-31: low 02:15 (-54 cm NAP), high 06:54 (+96 cm NAP), low 14:45 (-59 cm NAP), high 19:10 (+118 cm NAP)\n"
            "  Sun 2026-11-01: low 03:09 (-50 cm NAP), high 07:52 (+79 cm NAP), low 15:36 (-61 cm NAP), high 20:12 (+104 cm NAP)",
        )
        forecast = fake.matching("GET", "open-meteo")[0].params
        self.assertEqual((forecast["start_date"], forecast["end_date"]), ("2026-10-31", "2026-11-01"))
        tide = fake.matching("POST", "rijkswaterstaat")[0].body
        self.assertEqual(tide["Locatie"], {"Code": "ijmuiden.buitenhaven"})
        self.assertEqual(tide["Periode"]["Begindatumtijd"], "2026-10-31T00:00:00.000+01:00")

    def test_one_failed_source_leaves_the_other(self):
        fake = FakeNet().on("GET", "api.open-meteo.com", (503, {})).on("POST", "rijkswaterstaat.nl", TIDE)
        text = self.report(fake)
        self.assertIn("  unavailable: Open-Meteo HTTP 503", text)
        self.assertIn("high 06:54", text)

    def test_weekend_is_the_coming_saturday_and_sunday(self):
        self.assertEqual(weather.weekend(date(2026, 10, 30)), (date(2026, 10, 31), date(2026, 11, 1)))
        self.assertEqual(weather.weekend(date(2026, 10, 31)), (date(2026, 10, 31), date(2026, 11, 1)))
        self.assertEqual(weather.weekend(date(2026, 11, 2)), (date(2026, 11, 7), date(2026, 11, 8)))

    def test_beaufort_and_compass(self):
        self.assertEqual([weather.beaufort(k) for k in (0, 5, 19, 20, 38, 118)], [0, 1, 3, 4, 5, 12])
        self.assertEqual([weather.compass(d) for d in (0, 70, 225, 350)], ["N", "ENE", "SW", "N"])


if __name__ == "__main__":
    unittest.main()
