#!/usr/bin/env python3
"""Minimal stand-in for a Prometheus Pushgateway.

Appends every pushed request to a log file as "<path> <body>" so the tests can
assert which metrics and labels dumptruck reported. Requires basic auth, so a
credential regression shows up as a failed assertion rather than a silent pass.
"""
import base64
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

RECORD = os.environ.get("PUSHGATEWAY_LOG", "/work/pushed.log")
EXPECTED = "Basic " + base64.b64encode(b"push:push-secret-pw-do-not-log").decode()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.headers.get("Authorization") != EXPECTED:
            self.send_response(401)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode()

        with open(RECORD, "a") as f:
            for line in body.splitlines():
                if line and not line.startswith("#"):
                    f.write("{} {}\n".format(self.path, line))

        self.send_response(202)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
