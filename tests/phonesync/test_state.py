import os
import tempfile
import unittest

import state


class StateTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "phone.json")

    def tearDown(self):
        self.dir.cleanup()

    def test_load_missing_returns_empty(self):
        self.assertEqual(state.load(self.path), {})

    def test_save_then_load_roundtrip(self):
        data = {"items": {"/a.vcf": {"name": "Niccolò"}}, "sync_token": None}
        state.save(self.path, data)
        self.assertEqual(state.load(self.path), data)

    def test_save_is_atomic(self):
        state.save(self.path, {"a": 1})
        state.save(self.path, {"a": 2})
        self.assertEqual(os.listdir(self.dir.name), ["phone.json"])


if __name__ == "__main__":
    unittest.main()
