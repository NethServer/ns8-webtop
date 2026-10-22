import unittest

import transport
import webtop


class WebTopTest(unittest.TestCase):
    def test_call_encodes_path(self):
        sent = []
        real = transport.request

        def fake(method, url, **kw):
            sent.append(url)
            return transport.Response(204, {}, b"")
        transport.request = fake
        try:
            webtop.WebTop("http://x", "h", "u@d", "p", "webtop1").call("DELETE", "/cards/e2e a ☕.vcf")
        finally:
            transport.request = real
        self.assertEqual(sent, ["http://x/cards/e2e%20a%20%E2%98%95.vcf"])


if __name__ == "__main__":
    unittest.main()
