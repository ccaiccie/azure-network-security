#!/usr/bin/env bash
# FUTURE authorized upload/restart of this reviewed synthetic fixture only.
# No Terraform/check-local deployment. Tests use fake Azure CLI, never a real upload.
set -euo pipefail
umask 077
[[ "${1:-}" == --confirm-synthetic-origin-upload ]] || { printf 'Requires explicit authorization for code upload/restart; then use --confirm-synthetic-origin-upload REVIEWED_ZIP_SHA256.\n' >&2; exit 2; }
EXPECTED=${2:-}
[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] || { printf 'Supply the independently reviewed ZIP SHA256 as the second argument.\n' >&2; exit 2; }
EXPECTED=$(printf '%s' "$EXPECTED" | tr '[:upper:]' '[:lower:]')
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
python3 "$ROOT/scripts/build-origin.py"
# Private snapshot prevents subsequent source/build-file changes from altering the
# bytes uploaded. Compare this exact snapshot to the explicitly reviewed hash.
SNAPSHOT=$(mktemp -d)
trap 'rm -f "$SNAPSHOT/origin.zip"; rmdir "$SNAPSHOT"' EXIT
cp "$ROOT/build/origin.zip" "$SNAPSHOT/origin.zip"
chmod 0400 "$SNAPSHOT/origin.zip"
python3 - "$SNAPSHOT/origin.zip" "$EXPECTED" <<'PY'
import sys,zipfile,hashlib
from pathlib import Path
p=Path(sys.argv[1]);actual=hashlib.sha256(p.read_bytes()).hexdigest()
if actual!=sys.argv[2]:raise SystemExit('Package differs from reviewed SHA256; stop and review the new source/package before approval')
with zipfile.ZipFile(p) as z:
    assert set(z.namelist())=={'server.js','package.json'}
    assert all(b'PRIVATE KEY' not in z.read(name) and b'BEGIN CERTIFICATE' not in z.read(name) for name in z.namelist())
print('Reviewed package hash matched: '+actual)
PY
# CLI >=2.48.1 supports Entra fallback with basic publishing auth disabled.
# Runbook requires >=2.75 plus preinstalled approved firewall/Bastion extensions.
az webapp deploy --subscription "$SUBSCRIPTION_ID" --resource-group "$RG" --name "$ORIGIN" \
  --type zip --src-path "$SNAPSHOT/origin.zip" --clean true --restart true
printf 'Upload returned. Verify deployment status, direct HTTPS /allowed AND /blocked, certificate and fixture identity before setting origin_fixture_ready=true.\n'
