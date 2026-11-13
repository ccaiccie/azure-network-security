#!/usr/bin/env bash
# Authenticated context reads plus bounded HTTPS to this lab origin; no cloud mutation.
# Run from approved operator/32, outside the inspection path, with a PUBLIC normal
# origin-trust bundle that excludes the inspection root. Never substitute -k.
set -euo pipefail
umask 077
CA=${1:?Provide approved PUBLIC origin trust PEM excluding inspection CA}
OUT=${2:-"$PWD/evidence/origin-preflight-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
for tool in curl openssl realpath mktemp; do command -v "$tool" >/dev/null || exit 2; done
mkdir -p "$OUT"
python3 "$ROOT/scripts/public-ca-check.py" "$CA" > "$OUT/public-origin-ca-metadata.txt"
CA=$(realpath "$CA")
curl -V > "$OUT/curl-version.txt"
grep -q 'OpenSSL/' "$OUT/curl-version.txt" || { printf 'Require approved OpenSSL-backed curl.\n' >&2; exit 2; }
EMPTY=$(mktemp -d)
trap 'rmdir "$EMPTY"' EXIT
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR
for path in allowed blocked; do
  CASE_ID="direct-$path-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  curl -q -4 --http1.1 --tlsv1.2 --tls-max 1.2 --noproxy '*' --proxy '' \
    --cacert "$CA" --capath "$EMPTY" --connect-timeout 5 --max-time 20 \
    --silent --show-error --verbose --header "X-Lab-Case-ID: $CASE_ID" --user-agent "azure-tls-lab/$CASE_ID" \
    --dump-header "$OUT/$path.headers" --output "$OUT/$path.json" \
    --write-out 'http=%{http_code} verify=%{ssl_verify_result}\n' \
    "https://$H/$path" > "$OUT/$path.connection" 2> "$OUT/$path.stderr"
  python3 - "$OUT/$path.json" "$path" "$CASE_ID" "$OUT/$path.connection" <<'PY'
import json,sys
v=json.load(open(sys.argv[1])); c=open(sys.argv[4]).read().strip()
assert c=='http=200 verify=0',c
assert (v.get('fixture'),v.get('path'),v.get('case_id'))==('azure-tls-origin-v1','/'+sys.argv[2],sys.argv[3]),v
print('Direct origin fixture and normal trust matched:',sys.argv[2])
PY
done
printf 'Both paths verified from this operator. Review actual public chain/source restriction and retain evidence before origin_fixture_ready. No firewall inspection result inferred.\n'
