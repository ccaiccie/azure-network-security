#!/usr/bin/env bash
# Approved EXTERNAL client only. Each invocation makes one bounded synthetic request.
# Source is operator-declared; this script cannot discover or verify upstream NAT.
set -euo pipefail
umask 077
CASE_KIND=${1:-}; P=${2:-}; ALLOWED=${3:-}; DECLARED_SOURCE=${4:-}
case "$CASE_KIND" in positive|unpublished-port|excluded-source|publication-withdrawn|listener-unavailable|return-blackhole) ;; *)
  printf 'Usage: client-probe.sh CASE P ALLOWED_PUBLIC_IPV4/32 DECLARED_CURRENT_PUBLIC_IPV4 [evidence-directory]\n' >&2
  printf 'CASE: positive|unpublished-port|excluded-source|publication-withdrawn|listener-unavailable|return-blackhole\n' >&2; exit 2;;
esac
for tool in python3 curl date; do command -v "$tool" >/dev/null || { printf 'Missing preinstalled tool: %s\n' "$tool" >&2; exit 2; }; done
python3 - "$CASE_KIND" "$P" "$ALLOWED" "$DECLARED_SOURCE" <<'PY'
import ipaddress,sys
try:
    case,p,allowed,source=sys.argv[1:]
    target=ipaddress.IPv4Address(p)
    network=ipaddress.IPv4Network(allowed,strict=True)
    client=ipaddress.IPv4Address(source)
    assert target.is_global and not target.is_multicast
    assert network.prefixlen==32 and network.network_address.is_global and not network.network_address.is_multicast
    assert client.is_global and not client.is_multicast
    assert (client not in network) if case=='excluded-source' else (client in network)
except (ValueError,AssertionError):
    raise SystemExit('Supply actual public IPv4 identities and a /32. Excluded-source must be outside the allowed /32; other cases must use it. No request sent.')
PY
PORT=8443
[[ "$CASE_KIND" == unpublished-port ]] && PORT=8444
CASE_ID="dnat-$CASE_KIND-$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUT=${5:-"$PWD/evidence/$CASE_ID"}
mkdir -p "$OUT"
printf 'case=%s UTC=%s target=%s:%s protocol=plain-HTTP allowed=%s declared_public_source=%s (NOT independently verified)\n' \
  "$CASE_ID" "$(date -u +%FT%TZ)" "$P" "$PORT" "$ALLOWED" "$DECLARED_SOURCE" | tee "$OUT/case.txt"
set +e
curl -q -4 --http1.1 --noproxy '*' --connect-timeout 5 --max-time 15 \
  --silent --show-error --verbose \
  --dump-header "$OUT/response.headers" --output "$OUT/response.body" \
  --write-out 'http=%{http_code} local=%{local_ip}:%{local_port} remote=%{remote_ip}:%{remote_port} seconds=%{time_total}\n' \
  "http://$P:$PORT/$CASE_ID" > "$OUT/connection.txt" 2> "$OUT/curl.stderr"
RC=$?
set -e
printf 'curl_exit=%s\n' "$RC" | tee "$OUT/exit.txt"
cat "$OUT/connection.txt"
if [[ -f "$OUT/response.body" ]]; then cat "$OUT/response.body"; fi
tail -n 10 "$OUT/curl.stderr"
if [[ "$CASE_KIND" == positive && "$RC" -eq 0 ]]; then
  python3 - "$OUT/response.body" "$CASE_ID" "$OUT/connection.txt" <<'PY'
import ipaddress,json,sys
try:
    c=json.load(open(sys.argv[1],encoding='utf-8'))
    peer=ipaddress.IPv4Address(c.get('peer_ip',''))
    http200=open(sys.argv[3],encoding='utf-8').read().startswith('http=200 ')
    okay=(http200 and peer in ipaddress.IPv4Network('10.0.1.0/26') and c.get('server_ip')=='10.20.1.10'
          and c.get('server_port')==8080 and c.get('fixture_role')=='backend' and c.get('case')=='/'+sys.argv[2])
    print('TRANSLATED_FIXTURE_IDENTITY='+('MATCH' if okay else 'MISMATCH'))
    print('Observed backend peer I:q=',c.get('peer_ip'),':',c.get('peer_port'))
except (OSError,ValueError) as exc:
    print('TRANSLATED_FIXTURE_IDENTITY=UNVERIFIED:',exc)
PY
fi
printf 'RESULT=NEEDS_REVIEW. Check HTTP status, readiness, config, routes, original-source evidence and matching diagnostics. Evidence: %s\n' "$OUT"
if [[ "$CASE_KIND" != positive ]]; then
  printf 'No NAT Deny is expected for unmatched traffic. Failure or an absent NAT row alone is inconclusive.\n'
fi
