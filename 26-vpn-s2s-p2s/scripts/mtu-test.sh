#!/usr/bin/env bash
# Designed, not tested. Runs INSIDE vm-lan (for example through az vm run-command).
# Finds the largest packet that crosses the tunnel without fragmenting, using ping with the Don't Fragment bit set.
# The ICMP payload is the packet size minus 28 bytes of IP and ICMP header.
# Usage: mtu-test.sh [TARGET_IP] [START_SIZE]   (defaults: 10.60.1.10 and 1500)
TARGET="${1:-10.60.1.10}"
SIZE="${2:-1500}"
while [ "$SIZE" -ge 1200 ]; do
  if ping -M do -c 1 -W 2 -s $((SIZE - 28)) "$TARGET" > /dev/null 2>&1; then
    echo "largest packet that passed: $SIZE bytes (TCP MSS about $((SIZE - 40)))"
    exit 0
  fi
  echo "packet size $SIZE: no reply"
  SIZE=$((SIZE - 10))
done
echo "nothing passed down to 1200 bytes: this is not an MTU problem"
