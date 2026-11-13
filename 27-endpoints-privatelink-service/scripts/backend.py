#!/usr/bin/env python3
"""Tiny TCP backend for the Private Link Service lab (designed, not tested).

Listens on TCP 8080 and answers every request with one line of text:
  backend=<host> tcp_peer=<address that opened the connection> proxy_src=<address in the PROXY header or none> link_id=<hex or none>

It understands both modes of the service: without proxy protocol the peer is a NAT IP of the Private Link Service;
with TCP proxy protocol v2 the connection starts with a PROXY header that carries the original source address and a
LinkID TLV (type 0xEE). The TLV layout is read from memory: check current Microsoft docs.
"""
import socket
import struct
import threading

SIGNATURE = b"\r\n\r\n\x00\r\nQUIT\n"
HOST = socket.gethostname()


def parse_ppv2(data):
    """Return (source address, link id as hex or None) when data starts with a PROXY v2 header, else None."""
    if len(data) < 16 or not data.startswith(SIGNATURE):
        return None
    family = data[13] >> 4
    length = struct.unpack(">H", data[14:16])[0]
    body = data[16:16 + length]
    source, link, offset = None, None, 0
    if family == 1 and len(body) >= 12:
        source, offset = socket.inet_ntoa(body[0:4]), 12
    elif family == 2 and len(body) >= 36:
        source, offset = socket.inet_ntop(socket.AF_INET6, body[0:16]), 36
    tlv = body[offset:]
    while len(tlv) >= 3:
        kind = tlv[0]
        size = struct.unpack(">H", tlv[1:3])[0]
        value = tlv[3:3 + size]
        if kind == 0xEE and len(value) >= 5:
            link = value[1:5].hex()
        tlv = tlv[3 + size:]
    return source, link


def handle(conn, peer):
    try:
        conn.settimeout(3)
        try:
            data = conn.recv(4096)
        except socket.timeout:
            data = b""
        if not data:
            return
        parsed = parse_ppv2(data)
        source, link = parsed if parsed else (None, None)
        text = "backend=%s tcp_peer=%s proxy_src=%s link_id=%s\n" % (HOST, peer[0], source or "none", link or "none")
        body = text.encode()
        head = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(body)
        conn.sendall(head.encode() + body)
    except OSError:
        pass
    finally:
        conn.close()


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 8080))
    server.listen(128)
    while True:
        conn, peer = server.accept()
        threading.Thread(target=handle, args=(conn, peer), daemon=True).start()


if __name__ == "__main__":
    main()
