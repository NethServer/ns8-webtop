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


if __name__ == "__main__":
    unittest.main()
