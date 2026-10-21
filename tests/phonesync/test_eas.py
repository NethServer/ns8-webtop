import base64
import os
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET

import eas
from wbxml import find, findtext
from transport import HelperError


def el(tag, *children, text=None):
    e = ET.Element(tag)
    e.text = text
    for c in children:
        e.append(c)
    return e


def sync_reply(key, status="1", commands=(), more=False, responses=()):
    coll = el("AirSync:Collection", el("AirSync:SyncKey", text=key), el("AirSync:CollectionId", text="c1"),
              el("AirSync:Status", text=status))
    if commands:
        coll.append(el("AirSync:Commands", *commands))
    if more:
        coll.append(el("AirSync:MoreAvailable"))
    if responses:
        coll.append(el("AirSync:Responses", *responses))
    return el("AirSync:Sync", el("AirSync:Collections", coll))


def contact_add(server_id, name):
    return el("AirSync:Add", el("AirSync:ServerId", text=server_id),
              el("AirSync:ApplicationData", el("Contacts:FileAs", text=name)))


class FakeServer:
    """Answers post(cmd, root) calls from a queue of replies; records requests."""

    def __init__(self, *replies):
        self.replies = list(replies)
        self.requests = []

    def __call__(self, cmd, root):
        self.requests.append((cmd, root))
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


class EasTestCase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "phone.json")

    def tearDown(self):
        self.dir.cleanup()

    def client(self, server, profile="ios-eas", **state):
        c = eas.EasClient("http://x", "h", "u1@d", "pw", profile, self.path, post=server)
        c.state.update({"protocol": "14.0", "policy_key": "1",
                        "folders": [{"id": "c1", "type": "9", "name": "Contacts"}]})
        c.state.update(state)
        return c


class FolderTest(EasTestCase):
    def test_user_folders_used_when_no_default(self):
        c = self.client(FakeServer(), folders=[{"id": "i/1", "type": "2", "name": "Inbox"},
                                               {"id": "v/1", "type": "14", "name": "WebTop"},
                                               {"id": "c/2", "type": "13", "name": "WebTop"}])
        self.assertEqual(c.class_state("Contacts")["collection_id"], "v/1")
        self.assertEqual(c.class_state("Calendar")["collection_id"], "c/2")
        self.assertEqual(c.class_state("Email")["collection_id"], "i/1")


class NegotiateTest(unittest.TestCase):
    def test_current_zpush(self):
        self.assertEqual(eas.negotiate("12.0,12.1,14.0", "16.1"), "14.0")
        self.assertEqual(eas.negotiate("12.0,12.1,14.0", "14.1"), "14.0")

    def test_14_1_offered(self):
        self.assertEqual(eas.negotiate("2.5,12.0,12.1,14.0,14.1", "16.1"), "14.1")

    def test_16_offered_stays_on_14_1(self):
        self.assertEqual(eas.negotiate("14.0,14.1,16.0,16.1", "16.1"), "14.1")

    def test_too_old_server(self):
        with self.assertRaises(HelperError):
            eas.negotiate("2.5,12.0,12.1", "16.1")


class ProvisionTest(unittest.TestCase):
    def test_initial_request(self):
        root = eas.provision_request("14.0", eas.PROFILES["ios-eas"])
        self.assertEqual(findtext(root, ".//Provision:PolicyType"), "MS-EAS-Provisioning-WBXML")
        self.assertIsNone(find(root, ".//Provision:PolicyKey"))
        self.assertIsNone(find(root, "Settings:DeviceInformation"))

    def test_device_information_from_14_1(self):
        root = eas.provision_request("14.1", eas.PROFILES["android-eas"])
        self.assertEqual(findtext(root, "Settings:DeviceInformation/Settings:Set/Settings:UserAgent"),
                         eas.PROFILES["android-eas"]["user_agent"])

    def test_ack_request(self):
        root = eas.provision_request("14.0", eas.PROFILES["ios-eas"], temp_key="123")
        self.assertEqual(findtext(root, ".//Provision:PolicyKey"), "123")
        self.assertEqual(findtext(root, ".//Provision:Policy/Provision:Status"), "1")


class ItemShapeTest(unittest.TestCase):
    def test_timezone_blob_rome(self):
        blob = base64.b64decode(eas.timezone_blob("Europe/Rome"))
        self.assertEqual(len(blob), 172)
        bias, = struct.unpack_from("<l", blob, 0)
        self.assertEqual(bias, -60)
        std_month, std_dow, std_week, std_hour = struct.unpack_from("<2xHHHH", blob, 68)
        self.assertEqual((std_month, std_dow, std_week, std_hour), (10, 0, 5, 3))
        dst_bias, = struct.unpack_from("<l", blob, 168)
        self.assertEqual(dst_bias, -60)

    def test_calendar_data(self):
        data = eas.calendar_data("uid-1", "Riunione ☕", "2026-07-15T10:00:00", "2026-07-15T11:00:00", "Europe/Rome")
        self.assertEqual(findtext(data, "Calendar:StartTime"), "20260715T080000Z")
        self.assertEqual(findtext(data, "Calendar:EndTime"), "20260715T090000Z")
        self.assertEqual(findtext(data, "Calendar:Subject"), "Riunione ☕")
        self.assertEqual(findtext(data, "Calendar:UID"), "uid-1")
        self.assertEqual(findtext(data, "Calendar:Timezone"), eas.timezone_blob("Europe/Rome"))

    def test_calendar_data_in_utc(self):
        data = eas.calendar_data("u", "x", "2026-07-15T08:00:00Z", "2026-07-15T09:00:00Z", None)
        self.assertEqual(findtext(data, "Calendar:StartTime"), "20260715T080000Z")

    def test_contact_data_utf8(self):
        data = eas.contact_data("Niccolò Ürsula ☕")
        self.assertEqual(findtext(data, "Contacts:FileAs"), "Niccolò Ürsula ☕")
        self.assertEqual(eas.item_name(data), "Niccolò Ürsula ☕")

    def test_sendmail_request(self):
        root = eas.sendmail_request("cid", b"Subject: hi\r\n\r\nbody")
        self.assertEqual(root.tag, "ComposeMail:SendMail")
        self.assertEqual(findtext(root, "ComposeMail:ClientId"), "cid")
        self.assertIsNotNone(find(root, "ComposeMail:SaveInSentItems"))
        self.assertEqual(find(root, "ComposeMail:Mime").text, b"Subject: hi\r\n\r\nbody")


class SyncTest(EasTestCase):
    def test_initial_sync_then_paging(self):
        server = FakeServer(
            sync_reply("k1"),
            sync_reply("k2", commands=[contact_add("s1", "A"), contact_add("s2", "B")], more=True),
            sync_reply("k3", commands=[contact_add("s3", "C")]))
        out = self.client(server).sync("Contacts", window=2)
        self.assertEqual([i["name"] for i in out["added"]], ["A", "B", "C"])
        self.assertFalse(out["full_resync"])
        self.assertEqual(findtext(server.requests[0][1], ".//AirSync:SyncKey"), "0")
        self.assertEqual(findtext(server.requests[1][1], ".//AirSync:WindowSize"), "2")

    def test_incremental_sync_reports_changes_and_deletes(self):
        server = FakeServer(sync_reply("k5", commands=[
            el("AirSync:Change", el("AirSync:ServerId", text="s1"),
               el("AirSync:ApplicationData", el("Contacts:FileAs", text="A2"))),
            el("AirSync:Delete", el("AirSync:ServerId", text="s2"))]))
        c = self.client(server, sync={"Contacts": {"collection_id": "c1", "sync_key": "k4",
                                                   "items": {"s1": {"name": "A"}, "s2": {"name": "B"}}}})
        out = c.sync("Contacts")
        self.assertEqual(out["changed"], [{"server_id": "s1", "name": "A2", "start": None}])
        self.assertEqual(out["deleted"], ["s2"])
        self.assertEqual(c.state["sync"]["Contacts"]["sync_key"], "k5")

    def test_invalid_sync_key_reports_full_resync(self):
        server = FakeServer(sync_reply("0", status="3"), sync_reply("k1"),
                            sync_reply("k2", commands=[contact_add("s1", "A")]))
        c = self.client(server, sync={"Contacts": {"collection_id": "c1", "sync_key": "old",
                                                   "items": {"s1": {"name": "A"}}}})
        out = c.sync("Contacts")
        self.assertTrue(out["full_resync"])
        self.assertEqual(out["added"], [])  # same item came back: no duplicate

    def test_sync_reports_pages(self):
        server = FakeServer(
            sync_reply("k1"),
            sync_reply("k2", commands=[contact_add("s1", "A"), contact_add("s2", "B")], more=True),
            sync_reply("k3", commands=[contact_add("s3", "C")]))
        out = self.client(server).sync("Contacts", window=2)
        self.assertEqual((out["pages"], out["max_page"]), (2, 2))

    def test_delete_of_unknown_item_ignored(self):
        server = FakeServer(sync_reply("k5", commands=[el("AirSync:Delete", el("AirSync:ServerId", text="never-seen"))]))
        c = self.client(server, sync={"Contacts": {"collection_id": "c1", "sync_key": "k4", "items": {}}})
        self.assertEqual(c.sync("Contacts")["deleted"], [])

    def test_endless_more_available_raises(self):
        server = FakeServer(sync_reply("k1"), *[sync_reply("k%d" % i, more=True) for i in range(2, 60)])
        with self.assertRaises(HelperError):
            self.client(server).sync("Contacts")

    def test_repeated_invalid_sync_key_raises(self):
        server = FakeServer(sync_reply("0", status="3"), sync_reply("k1"), sync_reply("0", status="3"))
        c = self.client(server, sync={"Contacts": {"collection_id": "c1", "sync_key": "old", "items": {}}})
        with self.assertRaises(HelperError):
            c.sync("Contacts")

    def test_lookup_by_name(self):
        c = self.client(FakeServer(), sync={"Contacts": {"collection_id": "c1", "sync_key": "k1",
                                                         "items": {"s1": {"name": "A"}, "s2": {"name": "B"}}}})
        self.assertEqual(c.lookup("Contacts", "B"), {"server_id": "s2"})
        with self.assertRaises(HelperError):
            c.lookup("Contacts", "missing")

    def test_add_returns_server_id(self):
        server = FakeServer(sync_reply("k2", responses=[
            el("AirSync:Add", el("AirSync:ClientId", text="cid"), el("AirSync:ServerId", text="s9"),
               el("AirSync:Status", text="1"))]))
        c = self.client(server, sync={"Contacts": {"collection_id": "c1", "sync_key": "k1", "items": {}}})
        server_id = c.add("Contacts", "Z", client_id="cid")
        self.assertEqual(server_id, "s9")
        self.assertEqual(c.state["sync"]["Contacts"]["items"]["s9"]["name"], "Z")


if __name__ == "__main__":
    unittest.main()
