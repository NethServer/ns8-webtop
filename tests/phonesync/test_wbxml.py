import unittest
import xml.etree.ElementTree as ET

from wbxml import decode, encode


def folder_sync(key):
    root = ET.Element("FolderHierarchy:FolderSync")
    ET.SubElement(root, "FolderHierarchy:SyncKey").text = key
    return root


class WbxmlTest(unittest.TestCase):
    def test_roundtrip_foldersync(self):
        root = folder_sync("0")
        self.assertEqual(ET.tostring(decode(encode(root))), ET.tostring(root))

    def test_known_bytes_foldersync(self):
        # header 03 01 6A 00, SWITCH_PAGE 7, FolderSync(0x16|0x40), SyncKey(0x12|0x40), STR_I "0", END, END
        self.assertEqual(encode(folder_sync("0")),
                         bytes.fromhex("03016a00 0007 56 52 03 3000 01 01".replace(" ", "")))

    def test_utf8_text_roundtrip(self):
        root = ET.Element("AirSync:ApplicationData")
        ET.SubElement(root, "Contacts:FileAs").text = "Niccolò Ürsula ☕"
        self.assertEqual(decode(encode(root)).find("Contacts:FileAs").text, "Niccolò Ürsula ☕")

    def test_opaque_mime_roundtrip(self):
        mime = b"Subject: hi\r\n\r\nbody \xff\x00"
        root = ET.Element("ComposeMail:SendMail")
        ET.SubElement(root, "ComposeMail:Mime").text = mime
        data = encode(root)
        self.assertIn(b"\xc3", data)
        self.assertEqual(decode(data).find("ComposeMail:Mime").text, mime)

    def test_empty_element_has_no_content_bit(self):
        root = ET.Element("AirSync:Sync")
        ET.SubElement(root, "AirSync:GetChanges")
        decoded = decode(encode(root))
        self.assertIsNotNone(decoded.find("AirSync:GetChanges"))
        self.assertEqual(len(decoded.find("AirSync:GetChanges")), 0)

    def test_unknown_tag_raises(self):
        with self.assertRaises(KeyError):
            encode(ET.Element("AirSync:NoSuchTag"))


if __name__ == "__main__":
    unittest.main()
