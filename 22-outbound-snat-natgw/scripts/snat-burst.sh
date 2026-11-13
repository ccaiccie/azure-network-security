#!/usr/bin/env bash
# Designed, not tested. Runs INSIDE a lab VM (for example through az vm run-command).
# Opens N TCP connections at the same time to one destination and holds each for HOLD seconds,
# so every connection needs its own SNAT port. Prints how many connected and how many never did.
# Keep N small and use a destination you are allowed to test. This is a lab tool, not a load test.
# Usage: bash snat-burst.sh [N] [HOST] [PORT] [HOLD]
N="${1:-30}"
HOST="${2:-example.com}"
PORT="${3:-80}"
HOLD="${4:-15}"

tmp=$(mktemp -d)

for i in $(seq 1 "$N"); do
  # A connect that finds no SNAT port hangs until timeout kills it, and leaves no file behind.
  timeout $((HOLD + 5)) bash -c "exec 3<>/dev/tcp/$HOST/$PORT && echo ok > $tmp/$i && sleep $HOLD" 2>/dev/null &
done
wait

ok=$(ls "$tmp" | wc -l)
echo "attempted=$N connected=$ok never_connected=$((N - ok)) host=$HOST:$PORT"
rm -rf "$tmp"
