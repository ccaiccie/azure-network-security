#!/usr/bin/env python3
# Designed, not tested. A minimal UDP DNS forwarder: every query is sent unchanged to one upstream server
# and the answer is sent back. No cache, no TCP, no filtering. Lab use only.
# Usage: python3 /opt/lab/forward.py LISTEN_IP UPSTREAM_IP
import socket
import sys
import threading

listen_ip, upstream = sys.argv[1], sys.argv[2]
server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
server.bind((listen_ip, 53))


def handle(data, client):
    out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    out.settimeout(3)
    try:
        out.sendto(data, (upstream, 53))
        server.sendto(out.recv(4096), client)
    except OSError:
        pass  # no answer: the client times out, which is the symptom of a dead upstream
    finally:
        out.close()


while True:
    data, client = server.recvfrom(4096)
    threading.Thread(target=handle, args=(data, client), daemon=True).start()
