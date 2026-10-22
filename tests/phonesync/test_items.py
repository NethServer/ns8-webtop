import unittest

import items


class ItemsTest(unittest.TestCase):
    def test_vcard_roundtrip_name(self):
        data = items.vcard("uid-1", "Niccolò Ürsula ☕")
        self.assertIn("BEGIN:VCARD\r\n", data)
        self.assertIn("UID:uid-1\r\n", data)
        self.assertEqual(items.parse_name(data), "Niccolò Ürsula ☕")

    def test_name_escaping(self):
        data = items.vcard("uid-2", "Rossi, Mario; jr")
        self.assertIn("FN:Rossi\\, Mario\; jr\r\n", data)
        self.assertEqual(items.parse_name(data), "Rossi, Mario; jr")

    def test_event_with_timezone(self):
        data = items.event("uid-3", "Riunione", "2026-07-15T10:00:00", "2026-07-15T11:00:00", "Europe/Rome")
        self.assertIn("DTSTART;TZID=Europe/Rome:20260715T100000\r\n", data)
        self.assertIn("BEGIN:VTIMEZONE\r\nTZID:Europe/Rome\r\n", data)
        self.assertEqual(items.parse_name(data), "Riunione")
        self.assertEqual(items.parse_start(data), ("2026-07-15T10:00:00", "Europe/Rome"))

    def test_event_with_attendee(self):
        data = items.event("uid-5", "Meet", "2026-07-15T08:00:00Z", "2026-07-15T09:00:00Z", None,
                           attendees=["ann@example.org"])
        self.assertIn("ATTENDEE;CN=ann@example.org;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:"
                      "mailto:ann@example.org", items._unfold(data))
        self.assertNotIn("ATTENDEE", items.event("uid-6", "x", "2026-07-15T08:00:00Z", "2026-07-15T09:00:00Z", None))

    def test_event_in_utc(self):
        data = items.event("uid-4", "x", "2026-07-15T08:00:00Z", "2026-07-15T09:00:00Z", None)
        self.assertIn("DTSTART:20260715T080000Z\r\n", data)
        self.assertNotIn("VTIMEZONE", data)
        self.assertEqual(items.parse_start(data), ("2026-07-15T08:00:00Z", None))

    def test_parse_folded_lines(self):
        data = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Very long\r\n  name\r\nEND:VCARD\r\n"
        self.assertEqual(items.parse_name(data), "Very long name")

    def test_parse_name_ignores_vtimezone_and_valarm(self):
        data = items.event("uid-5", "Main", "2026-07-15T10:00:00", "2026-07-15T11:00:00", "Europe/Rome")
        data = data.replace("END:VEVENT", "BEGIN:VALARM\r\nSUMMARY:alarm\r\nEND:VALARM\r\nEND:VEVENT")
        self.assertEqual(items.parse_name(data), "Main")

    def test_with_name_contact(self):
        data = items.with_name(items.vcard("uid-6", "Old"), "Niccolò ☕")
        self.assertEqual(items.parse_name(data), "Niccolò ☕")
        self.assertIn("UID:uid-6\r\n", data)

    def test_with_name_event_keeps_times(self):
        server = ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTART;TZID=Europe/Rome:20260715T100000\r\n"
                  "SUMMARY:Old\r\n with fold\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
        data = items.with_name(server, "New")
        self.assertEqual(items.parse_name(data), "New")
        self.assertEqual(items.parse_start(data), ("2026-07-15T10:00:00", "Europe/Rome"))

    def test_test_png_is_valid(self):
        import zlib
        data = items.TEST_PNG
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        zlib.decompress(data[data.index(b"IDAT") + 4:data.index(b"IEND") - 8])

    def test_large_png_is_a_phone_sized_photo(self):
        import zlib
        data = items.LARGE_PNG
        self.assertTrue(20000 < len(data) < 40000)
        zlib.decompress(data[data.index(b"IDAT") + 4:data.index(b"IEND") - 8])
        self.assertEqual(items.LARGE_PNG, items.make_large_png())  # same bytes every run

    def test_vcard_large_photo(self):
        data = items.vcard("u", "x", {"photo": "large"})
        self.assertEqual(items.parse_fields(data)["photo_size"], len(items.LARGE_PNG))
        self.assertTrue(all(len(line.encode()) <= 75 for line in data.split("\r\n")))

    FIELDS = {"mobile": "+39 333 1234567", "email": "niccolo@example.test",
              "street": "Via Roma 1", "city": "Pesaro", "photo": "png"}

    def test_vcard_fields_roundtrip(self):
        data = items.vcard("uid-7", "Niccolò", self.FIELDS)
        self.assertIn("TEL;TYPE=CELL:+39 333 1234567\r\n", data)
        self.assertIn("EMAIL;TYPE=WORK:niccolo@example.test\r\n", data)
        self.assertTrue(all(len(line.encode()) <= 75 for line in data.split("\r\n")))
        self.assertEqual(items.parse_fields(data), {"mobile": "+39 333 1234567", "email": "niccolo@example.test",
                                                    "street": "Via Roma 1", "city": "Pesaro",
                                                    "photo_size": len(items.TEST_PNG)})

    def test_parse_fields_data_uri_photo(self):
        import base64
        data = ("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:x\r\nPHOTO:data:image/png;base64,%s\r\nEND:VCARD\r\n"
                % base64.b64encode(items.TEST_PNG).decode())
        self.assertEqual(items.parse_fields(data)["photo_size"], len(items.TEST_PNG))

    def test_parse_fields_missing(self):
        self.assertEqual(items.parse_fields(items.vcard("u", "x")),
                         {"mobile": None, "email": None, "street": None, "city": None, "photo_size": 0})

    def test_all_day_event(self):
        data = items.event("uid-8", "Ferie", "2026-07-15", "2026-07-16", None, all_day=True)
        self.assertIn("DTSTART;VALUE=DATE:20260715\r\n", data)
        self.assertIn("DTEND;VALUE=DATE:20260716\r\n", data)
        self.assertEqual(items.parse_event_details(data),
                         {"all_day": True, "start": "2026-07-15", "rrule": None, "alarm": None})

    def test_recurring_event_with_alarm(self):
        data = items.event("uid-9", "Weekly", "2026-07-15T10:00:00", "2026-07-15T11:00:00", "Europe/Rome",
                           rrule="FREQ=WEEKLY;COUNT=4", alarm=15)
        self.assertIn("RRULE:FREQ=WEEKLY;COUNT=4\r\n", data)
        self.assertIn("TRIGGER:-PT15M\r\n", data)
        self.assertEqual(items.parse_event_details(data),
                         {"all_day": False, "start": "2026-07-15T10:00:00", "rrule": "FREQ=WEEKLY;COUNT=4", "alarm": 15})

    def test_parse_alarm_hours(self):
        data = items.event("u", "x", "2026-07-15T10:00:00", "2026-07-15T11:00:00", "Europe/Rome", alarm=15)
        self.assertEqual(items.parse_event_details(data.replace("-PT15M", "-PT1H"))["alarm"], 60)

    def test_with_name_keeps_fields(self):
        data = items.with_name(items.vcard("u", "Old", self.FIELDS), "New")
        self.assertEqual(items.parse_fields(data)["photo_size"], len(items.TEST_PNG))
        self.assertEqual(items.parse_fields(data)["mobile"], "+39 333 1234567")


if __name__ == "__main__":
    unittest.main()
