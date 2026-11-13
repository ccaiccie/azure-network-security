#!/usr/bin/env bash
# INSIDE app: ew-probe positive | alternate-port
# INSIDE db:  ew-probe reverse-new
# Optional: app same-positive|same-alternate-port; c same-reverse-new.
# This collects evidence. Negative results require peer readiness + NSGs + firewall log.
set -euo pipefail
umask 077
CASE_KIND=${1:-}
case "$CASE_KIND" in positive|alternate-port|reverse-new|same-positive|same-alternate-port|same-reverse-new) ;; *)
  printf 'Usage: ew-probe positive|alternate-port|reverse-new|same-positive|same-alternate-port|same-reverse-new [evidence-directory]\n' >&2; exit 2;;
esac
for tool in python3 curl ip date; do
  command -v "$tool" >/dev/null || { printf 'Missing required preinstalled tool: %s\n' "$tool" >&2; exit 2; }
done
CONFIG=${EW_LAB_CONFIG:-/etc/azure-ew-lab.json}
CONFIG_LINES=$(python3 - "$CONFIG" <<'PY'
import ipaddress, json, sys
c=json.load(open(sys.argv[1], encoding="utf-8"))
assert c['role'] in ('app','db','c')
for key in ['private_ip','remote_ip']:
    assert ipaddress.ip_address(c[key]).version == 4
for key in ['role','private_ip','remote_ip']: print(c[key])
print('true' if c.get('same_vnet_enabled',False) else 'false')
print(c.get('same_vnet_ip','10.10.2.20'))
PY
)
mapfile -t SETTINGS <<< "$CONFIG_LINES"
ROLE=${SETTINGS[0]}; LOCAL_IP=${SETTINGS[1]}; REMOTE_IP=${SETTINGS[2]}
if ! ip -4 -o addr show | grep -Fq " $LOCAL_IP/"; then
  printf 'Wrong machine: expected private IP %s\n' "$LOCAL_IP" >&2; exit 2
fi
EXPECTED_ROLE=app
EXPECTED_SERVER_ROLE=db
case "$CASE_KIND" in
  reverse-new) EXPECTED_ROLE=db ;;
  same-reverse-new) EXPECTED_ROLE=c ;;
  same-positive|same-alternate-port) REMOTE_IP=${SETTINGS[4]}; EXPECTED_SERVER_ROLE=c ;;
esac
if [[ "$CASE_KIND" == same-* && "${SETTINGS[3]}" != true ]]; then
  printf 'Same-VNet variant is not enabled in this guest configuration.\n' >&2; exit 2
fi
if [[ "$ROLE" != "$EXPECTED_ROLE" ]]; then
  printf 'Wrong role %s for case %s\n' "$ROLE" "$CASE_KIND" >&2; exit 2
fi
PORT=8080
case "$CASE_KIND" in alternate-port|same-alternate-port) PORT=8081 ;; esac
CASE_ID="ew-$CASE_KIND-$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUT=${2:-"$HOME/ew-evidence/$CASE_ID"}
mkdir -p "$OUT"
printf 'case=%s UTC=%s source_role=%s target=%s:%s\n' "$CASE_ID" "$(date -u +%FT%TZ)" "$ROLE" "$REMOTE_IP" "$PORT" | tee "$OUT/case.txt"
set +e
curl -q -4 --http1.1 --noproxy '*' --connect-timeout 5 --max-time 15 \
  --silent --show-error --verbose \
  --dump-header "$OUT/response.headers" --output "$OUT/response.body" \
  --write-out 'http=%{http_code} local=%{local_ip}:%{local_port} remote=%{remote_ip}:%{remote_port} seconds=%{time_total}\n' \
  "http://$REMOTE_IP:$PORT/$CASE_ID" > "$OUT/connection.txt" 2> "$OUT/curl.stderr"
RC=$?
set -e
printf 'curl_exit=%s\n' "$RC" | tee "$OUT/exit.txt"
cat "$OUT/connection.txt"
if [[ -f "$OUT/response.body" ]]; then cat "$OUT/response.body"; fi
tail -n 10 "$OUT/curl.stderr"
if [[ ( "$CASE_KIND" == positive || "$CASE_KIND" == same-positive ) && "$RC" -eq 0 ]]; then
  python3 - "$OUT/response.body" "$LOCAL_IP" "$REMOTE_IP" "$CASE_ID" "$EXPECTED_SERVER_ROLE" <<'PY'
import json, sys
try:
    c=json.load(open(sys.argv[1], encoding='utf-8'))
    okay=(c.get('peer_ip')==sys.argv[2] and c.get('server_ip')==sys.argv[3]
          and c.get('server_port')==8080 and c.get('fixture_role')==sys.argv[5]
          and c.get('case')=='/'+sys.argv[4])
    print('FIXTURE_IDENTITY=' + ('MATCH' if okay else 'MISMATCH'))
except (OSError, ValueError) as exc:
    print('FIXTURE_IDENTITY=UNVERIFIED:', exc)
PY
fi
printf 'RESULT=NEEDS_REVIEW. No firewall verdict inferred from curl alone. Evidence: %s\n' "$OUT"
if [[ "$CASE_KIND" != positive && "$CASE_KIND" != same-positive ]]; then
  printf 'Require recent remote listener readiness, permitting effective NSGs and a matching named firewall Deny.\n'
fi
