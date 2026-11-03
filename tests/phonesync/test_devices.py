import os
import unittest

import devices

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "zpush-admin")


def fixture(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as f:
        return f.read()


class DevicesTest(unittest.TestCase):
    def test_parse_lastsync(self):
        rows = devices.parse_lastsync(fixture("lastsync.txt"))
        self.assertEqual(rows, [
            {"device": "e2eiphone0000001", "user": "u1@example.org", "last_sync": "2026-10-21 15:45"},
            {"device": "e2eandroid000001", "user": "u1@example.org", "last_sync": "2026-10-21 15:38"}])

    def test_parse_lastsync_never(self):
        text = "Device id  Synchronized user  Last sync time  Short Ids\n----\nabc  u@d  never  No\n"
        self.assertEqual(devices.parse_lastsync(text), [{"device": "abc", "user": "u@d", "last_sync": None}])

    def test_parse_lastsync_rejects_bad_date(self):
        text = "Device id  Synchronized user  Last sync time\n----\nabc  u@d  yesterday\n"
        with self.assertRaises(ValueError):
            devices.parse_lastsync(text)

    def test_parse_lastsync_without_header(self):
        self.assertEqual(devices.parse_lastsync("No devices found\n"), [])

    def test_parse_list(self):
        self.assertEqual(devices.parse_list(fixture("list.txt")),
                         {"e2eiphone0000001": ["u1@example.org"], "e2eandroid000001": ["u1@example.org"]})

    def test_parse_info(self):
        info = devices.parse_info(fixture("info.txt"))
        self.assertTrue(info.startswith("Synchronized by user: u1@example.org"))
        self.assertIn("Device type:", info)
        self.assertEqual(devices.parse_info("nothing here"), "")


if __name__ == "__main__":
    unittest.main()
