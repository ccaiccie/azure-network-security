#!/usr/bin/env bash
# Separate verified TLS handshake from app, not the same TCP tuple as a curl probe.
set -euo pipefail
umask 077
CA=${1:?Provide approved PUBLIC inspection CA PEM}
OUT=${2:-"$HOME/tls-evidence/chain-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
CONFIG=${TLS_LAB_CONFIG:-/etc/azure-tls-lab.json}
H=$(python3 - "$CONFIG" <<'PY'
import json,re,sys
h=json.load(open(sys.argv[1]))['origin_host']
assert re.fullmatch(r'[a-z0-9][a-z0-9.-]*\.azurewebsites\.net',h)
print(h)
PY
)
ip -4 -o addr show | grep -Fq ' 10.10.1.10/' || exit 2
mkdir -p "$OUT"
python3 "${TLS_CA_CHECKER:-/usr/local/lib/azure-tls/public-ca-check.py}" "$CA" > "$OUT/public-ca-metadata.txt"
openssl version > "$OUT/openssl-version.txt"
grep -q '^OpenSSL 3\.' "$OUT/openssl-version.txt" || { printf 'This capture profile requires approved OpenSSL3.\n' >&2; exit 2; }
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR
set +e
timeout 20 openssl s_client -4 -connect "$H:443" -servername "$H" -tls1_2 \
  -verify_hostname "$H" -verify_return_error -CAfile "$CA" -no-CApath -no-CAstore \
  -showcerts < /dev/null > "$OUT/chain.txt" 2> "$OUT/verify.txt"
RC=$?
set -e
printf 'UTC=%s host=%s exit=%s separate_connection=true\n' "$(date -u +%FT%TZ)" "$H" "$RC" | tee "$OUT/case.txt"
# Extract PUBLIC certificates only; never any key material.
python3 - "$OUT" <<'PY'
from pathlib import Path
import re,sys
out=Path(sys.argv[1]);data=(out/'chain.txt').read_text()
for i,pem in enumerate(re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',data,re.S),1):
    (out/f'peer-{i}.pem').write_text(pem+'\n')
PY
if [[ -f "$OUT/peer-1.pem" ]]; then openssl x509 -in "$OUT/peer-1.pem" -noout -subject -issuer -fingerprint -sha256 > "$OUT/leaf-metadata.txt"; fi
printf 'Review verification exit/output, hostname and approved CA chain. Issuer text alone is not proof; this is a separate handshake.\n'
exit "$RC"
