#!/usr/bin/env bash
# Inside A only; normal private DNS, original destination B, Host includes port.
set -euo pipefail
umask 077
KIND=${1:-}
case "$KIND" in allowed|denied|alternate-port) ;; *) printf 'Usage: policy-probe allowed|denied|alternate-port [OUT]\n' >&2; exit 2;; esac
for tool in python3 curl ip getent date; do command -v "$tool" >/dev/null || exit 2; done
CONFIG=${POLICY_LAB_CONFIG:-/etc/azure-policy-lab.json}
python3 - "$CONFIG" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]));assert c['role']=='app' and c['private_ip']=='10.10.1.10' and c['backend_ip']=='10.20.1.10'
assert c['allowed_host']=='allowed.policy.test' and c['denied_host']=='denied.policy.test'
for line in open('/etc/hosts'):
    aliases=line.split('#',1)[0].split()[1:]
    assert not {'allowed.policy.test','denied.policy.test'}.intersection(aliases),'Remove reviewed lab-host overrides before baseline DNS test'
PY
ip -4 -o addr show | grep -Fq ' 10.10.1.10/' || { printf 'Wrong client VM.\n' >&2; exit 2; }
HOST=allowed.policy.test; PORT=8080
[[ "$KIND" == denied ]] && HOST=denied.policy.test
[[ "$KIND" == alternate-port ]] && PORT=8081
CASE_ID="policy-$KIND-$(date -u +%Y%m%dT%H%M%SZ)-$$"
OUT=${2:-"$HOME/policy-evidence/$CASE_ID"}
# Atomic creation refuses every existing path (including empty directories/symlinks),
# so reruns cannot overwrite a prior case or reuse a stale response body.
mkdir -p -- "$(dirname -- "$OUT")"
if ! mkdir -- "$OUT"; then
  printf 'Evidence path already exists or cannot be created: %s. Choose a new OUT or omit it for a unique case directory.\n' "$OUT" >&2
  exit 2
fi
STARTED_UTC=$(date -u +%FT%TZ)
printf 'started_utc=%s\n' "$STARTED_UTC" > "$OUT/timing.txt"
trap 'status=$?; printf "completed_utc=%s\nshell_exit=%s\n" "$(date -u +%FT%TZ)" "$status" >> "$OUT/timing.txt"' EXIT
curl -V > "$OUT/curl-version.txt"
for name in allowed.policy.test denied.policy.test; do
  getent ahostsv4 "$name" > "$OUT/$name.dns"
  python3 - "$OUT/$name.dns" <<'PY'
import sys
rows=open(sys.argv[1]).read().splitlines();ips={r.split()[0] for r in rows if r.strip()}
assert ips=={'10.20.1.10'},'Unexpected or absent DNS answer: '+repr(ips)
PY
done
if command -v resolvectl >/dev/null; then resolvectl status > "$OUT/resolver-status.txt" || true; fi
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
printf 'case=%s UTC=%s A=10.10.1.10 B=10.20.1.10 url=http://%s:%s/probe\n' "$CASE_ID" "$(date -u +%FT%TZ)" "$HOST" "$PORT" | tee "$OUT/case.txt"
set +e
curl -q -4 --http1.1 --noproxy '*' --proxy '' --connect-timeout 5 --max-time 15 \
  --silent --show-error --verbose --header "X-Lab-Case-ID: $CASE_ID" \
  --user-agent "azure-policy-lab/$CASE_ID" --header 'Connection: close' \
  --dump-header "$OUT/response.headers" --output "$OUT/response.body" \
  --write-out 'http=%{http_code} local=%{local_ip}:%{local_port} remote=%{remote_ip}:%{remote_port} seconds=%{time_total}\n' \
  "http://$HOST:$PORT/probe" > "$OUT/connection.txt" 2> "$OUT/curl.stderr"
RC=$?
set -e
printf 'curl_exit=%s\n' "$RC" | tee "$OUT/exit.txt"
cat "$OUT/connection.txt"
if [[ -f "$OUT/response.body" ]]; then cat "$OUT/response.body"; fi
tail -n 10 "$OUT/curl.stderr"
python3 - "$OUT/response.body" "$CASE_ID" "$HOST:$PORT" "$PORT" "$OUT/connection.txt" <<'PY'
import ipaddress,json,sys
try:
    r=json.load(open(sys.argv[1]));conn=open(sys.argv[5]).read()
    okay=(r.get('fixture'),r.get('case_id'),r.get('host'),r.get('path'),r.get('server_ip'),r.get('server_port'))==('azure-policy-origin-v1',sys.argv[2],sys.argv[3],'/probe','10.20.1.10',int(sys.argv[4])) and conn.startswith('http=200 ')
    print('FIXTURE_IDENTITY='+('MATCH' if okay else 'MISMATCH'))
    if okay:
        peer=ipaddress.ip_address(r['peer_ip'])
        label='DIRECT_APP_SOURCE' if str(peer)=='10.10.1.10' else ('FIREWALL_SUBNET_PROXY_SOURCE' if peer in ipaddress.ip_network('10.0.1.0/26') else 'UNEXPECTED_SOURCE')
        print('BACKEND_PEER_CLASS='+label+' actual='+str(peer))
except (OSError,ValueError,KeyError) as exc:print('FIXTURE_IDENTITY=UNVERIFIED',exc)
PY
printf 'RESULT=NEEDS_REVIEW. Correlate current mode, deciding rule, actual route/NSGs, backend peer and case journal. No verdict from curl or missing log alone.\n'
