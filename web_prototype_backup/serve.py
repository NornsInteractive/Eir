#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Eir Dual-Stack Web Server (IPv4 + IPv6)
Listens on [::]:8080 to allow all IPv4 and IPv6 clients across all network interfaces.
"""

import sys
import os
import socket
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WEB_DIR = os.path.dirname(os.path.abspath(__file__))

class DualStackHTTPServer(ThreadingHTTPServer):
    address_family = socket.AF_INET6

    def server_bind(self):
        # Enable dual-stack: listen to both IPv6 and IPv4 on ::
        try:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except (AttributeError, OSError) as e:
            print(f"[Warning] Could not set IPV6_V6ONLY to 0: {e}")
        super().server_bind()

class CORSAndCacheHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        # Allow cross-origin access and instant updates during prototyping
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Cache-Control", "no-cache, must-revalidate")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

def main():
    os.chdir(WEB_DIR)
    server_address = ("::", PORT)
    try:
        httpd = DualStackHTTPServer(server_address, CORSAndCacheHandler)
        print(f"[Eir Server] Serving on dual-stack [::]:{PORT}")
        print(f"[Eir Server] Directory: {WEB_DIR}")
        print(f"[Eir Server] IPv4 access: http://127.0.0.1:{PORT} or http://192.168.1.106:{PORT}")
        print(f"[Eir Server] IPv6 access: http://[::1]:{PORT} or http://[240e:379:8e85:7c00:2334:cf34:ff28:35fb]:{PORT}")
        httpd.serve_forever()
    except Exception as e:
        print(f"[Error] Failed to start server on [::]:{PORT}: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
