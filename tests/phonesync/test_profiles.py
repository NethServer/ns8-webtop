import unittest

from profiles import PROFILES


class ProfilesTest(unittest.TestCase):
    def test_profiles_have_required_keys(self):
        self.assertEqual(set(PROFILES), {"davx5", "ios-dav", "ios-eas", "android-eas"})
        for name, profile in PROFILES.items():
            self.assertTrue(profile["user_agent"], name)
            if profile["protocol"] == "eas":
                self.assertIn(profile["max_protocol"], {"14.1", "16.1"})
                self.assertTrue(profile["device_id"])
                self.assertTrue(profile["device_type"])
            else:
                self.assertEqual(profile["protocol"], "dav")
                self.assertIn(profile["strategy"], {"sync-collection", "ctag"})


if __name__ == "__main__":
    unittest.main()
