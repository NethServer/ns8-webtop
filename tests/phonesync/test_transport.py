import http.server
import os
import shutil
import ssl
import subprocess
import tempfile
import threading
import unittest
import urllib.error

import transport


class _Ok(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


@unittest.skipUnless(shutil.which("openssl"), "needs openssl to make a certificate")
class InsecureTest(unittest.TestCase):
    """The node's own Traefik serves a self-signed certificate for the WebTop host name."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        cert, key = os.path.join(self.tmp, "cert.pem"), os.path.join(self.tmp, "key.pem")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=webtop.example.test", "-keyout", key, "-out", cert],
                       check=True, capture_output=True)
        self.server = http.server.HTTPServer(("127.0.0.1", 0), _Ok)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        self.server.socket = ctx.wrap_socket(self.server.socket, server_side=True)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "https://127.0.0.1:%d/" % self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        shutil.rmtree(self.tmp)

    def get(self, **kw):
        return transport.request("GET", self.url, user="u", password="p", host="webtop.example.test",
                                 timeout=10, **kw)

    def test_insecure_skips_certificate_check(self):
        self.assertEqual(self.get(insecure=True).status, 200)

    def test_certificate_checked_by_default(self):
        with self.assertRaises(urllib.error.URLError) as err:
            self.get()
        self.assertIn("CERTIFICATE_VERIFY_FAILED", str(err.exception))


if __name__ == "__main__":
    unittest.main()
