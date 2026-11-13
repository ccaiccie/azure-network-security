#!/usr/bin/env bash
# Inside app only. Process-local PUBLIC trust; no trust-store mutation or bypass.
set -euo pipefail
umask 077
CASE=${1:-}; CA=${2:-}; OUT=${3:-"$HOME/tls-evidence/tls-$CASE-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
PIN=${4:-}
case "$CASE" in allowed|blocked|untrusted|origin-pin) ;; *) printf 'Usage: tls-probe allowed|blocked|untrusted|origin-pin PUBLIC_CA_PEM [OUT] [approved-origin-sha256-pin]\n' >&2; exit 2;; esac
for tool in python3 curl openssl getent ip date mktemp realpath; do command -v "$tool" >/dev/null || exit 2; done
CONFIG=${TLS_LAB_CONFIG:-/etc/azure-tls-lab.json}
SETTINGS=$(python3 - "$CONFIG" <<'PY'
import json,re,sys
c=json.load(open(sys.argv[1]))
assert c['app_ip']=='10.10.1.10'
assert re.fullmatch(r'[a-z0-9][a-z0-9.-]*\.azurewebsites\.net',c['origin_host'])
print(c['app_ip']);print(c['origin_host']);print(c['firewall_ip'])
PY
)
mapfile -t VALUE <<< "$SETTINGS"
A=${VALUE[0]}; H=${VALUE[1]}; F=${VALUE[2]}
ip -4 -o addr show | grep -Fq " $A/" || { printf 'Wrong client VM.\n' >&2; exit 2; }
# The checker is delivered with this helper; it reads only PUBLIC certificates.
CHECKER=${TLS_CA_CHECKER:-/usr/local/lib/azure-tls/public-ca-check.py}
mkdir -p "$OUT"
python3 "$CHECKER" "$CA" > "$OUT/public-ca-metadata.txt"
CA=$(realpath "$CA")
curl -V > "$OUT/curl-version.txt"
grep -q 'OpenSSL/' "$OUT/curl-version.txt" || { printf 'Require approved OpenSSL-backed curl for isolated CA-path tests.\n' >&2; exit 2; }
EMPTY=$(mktemp -d)
trap 'rmdir "$EMPTY"' EXIT
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR
getent ahostsv4 "$H" > "$OUT/dns-answers.txt"
if command -v resolvectl >/dev/null; then resolvectl status > "$OUT/resolver-status.txt" || true; fi
PATH_PART=allowed
[[ "$CASE" == blocked ]] && PATH_PART=blocked
CASE_ID="tls-$CASE-$(date -u +%Y%m%dT%H%M%SZ)-$$"
printf 'case=%s UTC=%s A=%s H=%s F=%s path=/%s CA=%s\n' "$CASE_ID" "$(date -u +%FT%TZ)" "$A" "$H" "$F" "$PATH_PART" "$CA" | tee "$OUT/case.txt"
EXTRA=()
if [[ "$CASE" == origin-pin ]]; then
  [[ "$PIN" =~ ^sha256//[A-Za-z0-9+/]{43}=$ ]] || { printf 'Require independently verified approved origin SPKI sha256// pin.\n' >&2; exit 2; }
  EXTRA=(--pinnedpubkey "$PIN")
fi
set +e
curl -q -4 --http1.1 --tlsv1.2 --tls-max 1.2 --noproxy '*' --proxy '' \
  --cacert "$CA" --capath "$EMPTY" --connect-timeout 5 --max-time 20 \
  --silent --show-error --verbose --header "X-Lab-Case-ID: $CASE_ID" --user-agent "azure-tls-lab/$CASE_ID" \
  --dump-header "$OUT/response.headers" --output "$OUT/response.body" \
  --write-out 'http=%{http_code} verify=%{ssl_verify_result} local=%{local_ip}:%{local_port} remote=%{remote_ip}:%{remote_port} seconds=%{time_total}\n' \
  "${EXTRA[@]}" "https://$H/$PATH_PART" > "$OUT/connection.txt" 2> "$OUT/curl.stderr"
RC=$?
set -e
printf 'curl_exit=%s\n' "$RC" | tee "$OUT/exit.txt"
cat "$OUT/connection.txt"
if [[ -f "$OUT/response.body" ]]; then cat "$OUT/response.body"; fi
tail -n 12 "$OUT/curl.stderr"
if [[ "$CASE" == allowed && "$RC" -eq 0 ]]; then
  python3 - "$OUT/response.body" "$CASE_ID" "$OUT/connection.txt" <<'PY'
import json,sys
try:
    r=json.load(open(sys.argv[1]));connection=open(sys.argv[3]).read()
    okay=(r.get('fixture')=='azure-tls-origin-v1' and r.get('path')=='/allowed' and r.get('case_id')==sys.argv[2]
          and connection.startswith('http=200 verify=0 '))
    print('ORIGIN_IDENTITY='+('MATCH' if okay else 'MISMATCH'))
except (OSError,ValueError) as exc:print('ORIGIN_IDENTITY=UNVERIFIED',exc)
PY
fi
printf 'RESULT=NEEDS_REVIEW. Require route, verified inspection chain, exact application decision/IsTlsInspected and origin evidence. No verdict inferred from curl alone.\n'
