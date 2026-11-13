#!/usr/bin/env python3
# Designed, not tested. A tiny DNS client that uses only the Python standard library.
# Usage: python3 /opt/lab/dnsq.py NAME [SERVER] [TYPE]     default server 168.63.129.16, default type A
# It prints the response code, then each answer record as: name  TTL  TYPE  data (CNAME chains appear in order).
import random
import socket
import struct
import sys

TYPES = {"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "PTR": 12, "TXT": 16, "AAAA": 28}
NAMES = {v: k for k, v in TYPES.items()}
RCODES = {0: "NOERROR", 1: "FORMERR", 2: "SERVFAIL", 3: "NXDOMAIN", 5: "REFUSED"}


def build(name, qtype):
    head = struct.pack(">HHHHHH", random.randint(0, 65535), 0x0100, 1, 0, 0, 0)
    question = b"".join(bytes([len(p)]) + p.encode() for p in name.rstrip(".").split(".")) + b"\0"
    return head + question + struct.pack(">HH", qtype, 1)


def read_name(buf, pos):
    labels, end, jumped = [], pos, False
    while True:
        n = buf[pos]
        if n == 0:
            if not jumped:
                end = pos + 1
            return ".".join(labels), end
        if n & 0xC0 == 0xC0:
            if not jumped:
                end = pos + 2
            pos = ((n & 0x3F) << 8) | buf[pos + 1]
            jumped = True
        else:
            labels.append(buf[pos + 1:pos + 1 + n].decode())
            pos += 1 + n


def main():
    name = sys.argv[1]
    server = sys.argv[2] if len(sys.argv) > 2 else "168.63.129.16"
    qtype = TYPES[sys.argv[3].upper()] if len(sys.argv) > 3 else 1
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    try:
        sock.sendto(build(name, qtype), (server, 53))
        buf, _ = sock.recvfrom(4096)
    except OSError:
        print("%s @%s: TIMEOUT (no answer in 3 s)" % (name, server))
        return 1
    _, flags, qd, an, _, _ = struct.unpack(">HHHHHH", buf[:12])
    print("%s @%s: %s, %d answer record(s)" % (name, server, RCODES.get(flags & 15, str(flags & 15)), an))
    pos = 12
    for _ in range(qd):
        _, pos = read_name(buf, pos)
        pos += 4
    for _ in range(an):
        rname, pos = read_name(buf, pos)
        rtype, _, ttl, rdlen = struct.unpack(">HHIH", buf[pos:pos + 10])
        pos += 10
        if rtype == 1:
            data = socket.inet_ntoa(buf[pos:pos + 4])
        elif rtype in (2, 5, 12):
            data = read_name(buf, pos)[0]
        else:
            data = buf[pos:pos + rdlen].hex()
        print("  %s  %d  %s  %s" % (rname, ttl, NAMES.get(rtype, rtype), data))
        pos += rdlen
    return 0


sys.exit(main())
