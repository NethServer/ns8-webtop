"""Minimal HTTP client: Basic auth, forwarded headers, redirects not followed."""

import base64
import ssl
import urllib.error
import urllib.request


class HelperError(Exception):
    def __init__(self, message, http_status=None):
        super().__init__(message)
        self.http_status = http_status


class Response:
    def __init__(self, status, headers, body):
        self.status = status
        self.headers = {k.lower(): v for k, v in headers.items()}
        self.body = body


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(_NoRedirect)
# for the node's own Traefik, which serves a self-signed certificate
_insecure_opener = urllib.request.build_opener(
    _NoRedirect, urllib.request.HTTPSHandler(context=ssl._create_unverified_context()))


def request(method, url, *, user, password, host, headers=None, body=None, timeout=60, insecure=False):
    all_headers = {
        "Host": host,
        "X-Forwarded-Host": host,
        "X-Forwarded-Proto": "https",
        "Authorization": "Basic " + base64.b64encode(("%s:%s" % (user, password)).encode()).decode(),
    }
    all_headers.update(headers or {})
    req = urllib.request.Request(url, data=body, headers=all_headers, method=method)
    try:
        with (_insecure_opener if insecure else _opener).open(req, timeout=timeout) as resp:
            return Response(resp.status, dict(resp.headers), resp.read())
    except urllib.error.HTTPError as err:
        return Response(err.code, dict(err.headers), err.read())
