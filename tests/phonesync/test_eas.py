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

    def test_16_offered_to_ios_fails_loudly(self):
        # a real iPhone would use 16.x: running it on 14.1 would test the wrong thing
        with self.assertRaises(HelperError):
            eas.negotiate("14.0,14.1,16.0,16.1", "16.1")

    def test_16_offered_to_android_uses_14_1(self):
        self.assertEqual(eas.negotiate("14.0,14.1,16.0,16.1", "14.1"), "14.1")

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

    def test_parse_timezone_blob(self):
        tz = eas.parse_timezone(eas.timezone_blob("Europe/Rome"))
        self.assertEqual(tz, {"bias": -60, "dst_bias": -60, "std_month": 10, "dst_month": 3})
        self.assertIsNone(eas.parse_timezone(None))

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

    FIELDS = {"mobile": "+39 333 1234567", "email": "niccolo@example.test",
              "street": "Via Roma 1", "city": "Pesaro", "photo": "png"}

    def test_task_data(self):
        data = eas.task_data("Pay ☕", "2026-07-20T08:00:00Z")
        self.assertEqual(findtext(data, "Tasks:Subject"), "Pay ☕")
        self.assertEqual(findtext(data, "Tasks:UtcDueDate"), "2026-07-20T08:00:00.000Z")
        self.assertEqual(findtext(data, "Tasks:Complete"), "0")
        self.assertIsNone(find(data, "Tasks:DateCompleted"))

    def test_task_complete_data(self):
        data = eas.task_data("Pay", "2026-07-20T08:00:00Z", complete=True)
        self.assertEqual(findtext(data, "Tasks:Complete"), "1")
        self.assertRegex(findtext(data, "Tasks:DateCompleted"), r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.000Z$")

    def test_contact_fields_data(self):
        data = eas.contact_data("N", self.FIELDS)
        self.assertEqual(findtext(data, "Contacts:MobilePhoneNumber"), "+39 333 1234567")
        self.assertEqual(findtext(data, "Contacts:Email1Address"), "niccolo@example.test")
        self.assertEqual(findtext(data, "Contacts:BusinessStreet"), "Via Roma 1")
        self.assertEqual(findtext(data, "Contacts:BusinessCity"), "Pesaro")
        self.assertEqual(base64.b64decode(findtext(data, "Contacts:Picture")), eas.items.TEST_PNG)
        self.assertEqual(eas.contact_fields(data), {"mobile": "+39 333 1234567", "email": "niccolo@example.test",
                                                    "street": "Via Roma 1", "city": "Pesaro",
                                                    "photo_size": len(eas.items.TEST_PNG)})

    def test_contact_large_photo(self):
        data = eas.contact_data("N", {"photo": "large"})
        self.assertEqual(base64.b64decode(findtext(data, "Contacts:Picture")), eas.items.LARGE_PNG)

    def test_calendar_all_day(self):
        data = eas.calendar_data("u", "Ferie", "2026-07-15", "2026-07-16", "Europe/Rome", all_day=True)
        self.assertEqual(findtext(data, "Calendar:AllDayEvent"), "1")
        self.assertEqual(findtext(data, "Calendar:StartTime"), "20260714T220000Z")  # local midnight
        self.assertEqual(findtext(data, "Calendar:EndTime"), "20260715T220000Z")
        self.assertEqual(eas.event_details(data)["start"], "2026-07-15")
        self.assertTrue(eas.event_details(data)["all_day"])

    def test_calendar_recurrence_and_reminder(self):
        data = eas.calendar_data("u", "Weekly", "2026-07-15T10:00:00", "2026-07-15T11:00:00", "Europe/Rome",
                                 rrule="FREQ=WEEKLY;COUNT=4", alarm=15)
        self.assertEqual(findtext(data, "Calendar:Recurrence/Calendar:Type"), "1")
        self.assertEqual(findtext(data, "Calendar:Recurrence/Calendar:Occurrences"), "4")
        self.assertEqual(findtext(data, "Calendar:Recurrence/Calendar:DayOfWeek"), "8")  # Wednesday
        self.assertEqual(findtext(data, "Calendar:Reminder"), "15")
        self.assertEqual(eas.event_details(data), {"all_day": False, "start": "2026-07-15T08:00:00Z",
                                                   "rrule": "FREQ=WEEKLY;COUNT=4", "alarm": 15})

    def test_unsupported_rrule_raises(self):
        with self.assertRaises(HelperError):
            eas.calendar_data("u", "x", "2026-07-15T10:00:00", "2026-07-15T11:00:00", "Europe/Rome",
                              rrule="FREQ=MONTHLY;BYDAY=2TU")

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
        self.assertEqual(out["changed"], [{"server_id": "s1", "name": "A2", "start": None,
                                           "tz_bias": None, "tz_dst_bias": None,
                                           "fields": {"mobile": None, "email": None, "street": None,
                                                      "city": None, "photo_size": 0}}])
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

    def test_sync_reports_event_timezone(self):
        event = el("AirSync:Add", el("AirSync:ServerId", text="e1"), el("AirSync:ApplicationData",
                   el("Calendar:Timezone", text=eas.timezone_blob("Europe/Rome")),
                   el("Calendar:Subject", text="M"), el("Calendar:StartTime", text="20260715T080000Z")))
        c = self.client(FakeServer(sync_reply("k1"), sync_reply("k2", commands=[event])),
                        folders=[{"id": "c1", "type": "13", "name": "WebTop"}])
        added = c.sync("Calendar")["added"][0]
        self.assertEqual((added["start"], added["tz_bias"], added["tz_dst_bias"]), ("2026-07-15T08:00:00Z", -60, -60))

    def test_sync_entries_carry_fields(self):
        contact = el("AirSync:Add", el("AirSync:ServerId", text="v1"), el("AirSync:ApplicationData",
                     el("Contacts:FileAs", text="N"), el("Contacts:MobilePhoneNumber", text="+39 1"),
                     el("Contacts:Picture", text=base64.b64encode(eas.items.TEST_PNG).decode())))
        task = el("AirSync:Add", el("AirSync:ServerId", text="t1"), el("AirSync:ApplicationData",
                  el("Tasks:Subject", text="T"), el("Tasks:Complete", text="1"),
                  el("Tasks:UtcDueDate", text="2026-07-20T08:00:00.000Z")))
        c = self.client(FakeServer(sync_reply("k1"), sync_reply("k2", commands=[contact]),
                                   sync_reply("k1"), sync_reply("k2", commands=[task])),
                        folders=[{"id": "v/1", "type": "14", "name": "WebTop"}, {"id": "t/1", "type": "15", "name": "WebTop"}])
        added = c.sync("Contacts")["added"][0]
        self.assertEqual(added["fields"]["mobile"], "+39 1")
        self.assertEqual(added["fields"]["photo_size"], len(eas.items.TEST_PNG))
        added = c.sync("Tasks")["added"][0]
        self.assertEqual((added["name"], added["complete"], added["due"]), ("T", True, "2026-07-20T08:00:00Z"))

    def ping_client(self, server):
        return self.client(server, folders=[{"id": "i/1", "type": "2", "name": "Inbox"}],
                           sync={"Email": {"collection_id": "i/1", "sync_key": "k1", "items": {}}})

    def test_ping_request_shape(self):
        server = FakeServer(el("Ping:Ping", el("Ping:Status", text="1"), el("Ping:Folders")))
        out = self.ping_client(server).ping(["Email"], 45)
        cmd, root = server.requests[0]
        self.assertEqual((cmd, root.tag), ("Ping", "Ping:Ping"))
        self.assertEqual(findtext(root, "Ping:LifeTime"), "45")
        self.assertEqual(findtext(root, "Ping:Folders/Ping:Folder/Ping:ServerEntryId"), "i/1")
        self.assertEqual(findtext(root, "Ping:Folders/Ping:Folder/Ping:FolderType"), "Email")
        self.assertEqual((out["status"], out["folders"]), (1, []))
        self.assertIsInstance(out["seconds"], float)

    def test_ping_parses_changed_folders(self):
        server = FakeServer(el("Ping:Ping", el("Ping:Status", text="2"), el("Ping:Folders", el("Ping:Folder", text="i/1"))))
        out = self.ping_client(server).ping(["Email"], 45)
        self.assertEqual((out["status"], out["folders"]), (2, ["i/1"]))

    def test_ping_requires_synced_folders(self):
        c = self.client(FakeServer(), folders=[{"id": "v/1", "type": "14", "name": "WebTop"}])
        with self.assertRaises(HelperError):
            c.ping(["Contacts"], 45)

    def test_write_without_reply_fails_clearly(self):
        c = self.client(FakeServer(None), sync={"Contacts": {"collection_id": "c1", "sync_key": "k1", "items": {}}})
        with self.assertRaisesRegex(HelperError, "empty reply"):
            c.add("Contacts", "Z")

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
