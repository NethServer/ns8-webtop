import os
import unittest

import dav

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "dav")
BASE = "/webtop-dav/server.php"
AB = BASE + "/addressbooks/u1@example.org/3i2NDaWmqGVd2Q/"
CAL = BASE + "/calendars/u1@example.org/3i2NDaWmqGVd2R/"
CARD = AB + "28c7fd14-2ff8-4cc0-aed6-f7a935f1ae6c.vcf"
EVENT = CAL + "9c82e01e-349d-4ac7-a3d0-d3924f539542.ics"


def fixture(name):
    with open(os.path.join(FIXTURES, name), "rb") as f:
        return f.read()


class DiscoveryTest(unittest.TestCase):
    def test_parse_principal(self):
        self.assertEqual(dav.principal_href(fixture("principal.xml")), BASE + "/principals/u1@example.org/")

    def test_parse_home_sets(self):
        self.assertEqual(dav.home_sets(fixture("homes.xml")),
                         (BASE + "/calendars/u1@example.org/", BASE + "/addressbooks/u1@example.org/"))

    def test_parse_addressbooks(self):
        self.assertEqual(dav.collections(fixture("addressbook-home.xml"), "contact"), [{
            "href": AB, "displayname": "WebTop", "ctag": "20261021071013000",
            "sync_token": "http://sabre.io/ns/sync/20261021071013000"}])

    def test_parse_calendars_with_vevent(self):
        cals = dav.collections(fixture("calendar-home.xml"), "event")
        self.assertEqual([c["href"] for c in cals], [CAL])


class ListingTest(unittest.TestCase):
    def test_etags_skip_collection(self):
        self.assertEqual(dav.etags(fixture("calendar-etags.xml")), {EVENT: '"20261021071014000"'})

    def test_sync_collection_result(self):
        changes, token = dav.sync_result(fixture("sync-initial.xml"))
        self.assertEqual(changes, {CARD: '"20261021071013000"'})
        self.assertEqual(token, "http://sabre.io/ns/sync/20261021071013000")

    def test_invalid_sync_token(self):
        self.assertTrue(dav.is_invalid_sync_token(403, fixture("sync-invalid.xml")))
        self.assertFalse(dav.is_invalid_sync_token(207, fixture("sync-initial.xml")))

    def test_multiget_contact(self):
        got = dav.multiget(fixture("addressbook-multiget.xml"))
        etag, data = got[CARD]
        self.assertEqual(etag, '"20261021071013000"')
        self.assertEqual(dav.items.parse_name(data), "e2e-fixture-Niccolò Ürsula ☕")

    def test_multiget_event(self):
        etag, data = dav.multiget(fixture("calendar-multiget.xml"))[EVENT]
        self.assertEqual(dav.items.parse_start(data), ("2026-07-15T10:00:00", "Europe/Rome"))


class DiffTest(unittest.TestCase):
    STATE = {"/a.vcf": {"etag": '"1"'}, "/b.vcf": {"etag": '"1"'}, "/c.vcf": {"etag": '"1"'}}

    def test_incremental_listing(self):
        # sync-collection: unchanged items may be repeated, deletions come as None
        listing = {"/a.vcf": '"1"', "/b.vcf": '"2"', "/c.vcf": None, "/d.vcf": '"1"'}
        self.assertEqual(dav.diff(self.STATE, listing, complete=False), (["/d.vcf"], ["/b.vcf"], ["/c.vcf"]))

    def test_complete_listing(self):
        # ctag strategy: whatever is missing from the full listing was deleted
        listing = {"/a.vcf": '"1"', "/d.vcf": '"1"'}
        self.assertEqual(dav.diff(self.STATE, listing, complete=True), (["/d.vcf"], [], ["/b.vcf", "/c.vcf"]))

    def test_deleted_unknown_item_ignored(self):
        self.assertEqual(dav.diff({}, {"/x.vcf": None}, complete=False), ([], [], []))


class LookupTest(unittest.TestCase):
    def test_lookup_by_name_in_state(self):
        import tempfile, json
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "s.json")
            with open(path, "w") as f:
                json.dump({"contact": {"collection": AB, "items": {CARD: {"etag": '"1"', "name": "A"},
                                                                  AB + "x.vcf": {"etag": '"1"', "name": "A"}}}}, f)
            client = dav.DavClient("http://x", "h", "u", "p", "davx5", path)
            with self.assertRaises(dav.HelperError):  # two items with the same name: not exactly one
                client.lookup("contact", "A")
            with self.assertRaises(dav.HelperError):
                client.lookup("contact", "B")
            client.state["contact"]["items"][AB + "y.vcf"] = {"etag": '"1"', "name": "C"}
            self.assertEqual(client.lookup("contact", "C"), {"href": AB + "y.vcf"})


if __name__ == "__main__":
    unittest.main()
