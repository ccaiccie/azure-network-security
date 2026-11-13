#!/usr/bin/env bash
# Future explicit synthetic code upload/restart, never part of local checks.
set -euo pipefail
umask 077
[[ $# == 3 && "$1" == --confirm-synthetic-origin-upload && "$3" =~ ^[0-9a-fA-F]{64}$ ]] || { printf 'Usage: deploy-origin.sh --confirm-synthetic-origin-upload REVIEWED_ZIP REVIEWED_SHA256\n' >&2; exit 2; }
ZIP=$2
EXPECTED=$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
[[ "$(read_output publication_enabled)" == true ]] || { printf 'SCM publication gate is closed.\n' >&2; exit 2; }
SNAPSHOT=$(mktemp -d)
trap 'rm -f "$SNAPSHOT/origin.zip"; rmdir "$SNAPSHOT"' EXIT
python3 - "$ZIP" "$SNAPSHOT/origin.zip" "$EXPECTED" <<'CHECK'
from pathlib import Path
import hashlib,io,os,sys,zipfile
p=Path(sys.argv[1]);target=Path(sys.argv[2])
if p.is_symlink() or any(x.is_symlink() for x in p.parents) or not p.is_file():raise SystemExit('Reviewed ZIP must be an ordinary nonsymlink file')
b=p.read_bytes()
if len(b)>262144 or hashlib.sha256(b).hexdigest()!=sys.argv[3]:raise SystemExit('Reviewed immutable package hash/size mismatch; upload refused')
with zipfile.ZipFile(io.BytesIO(b)) as z:
 if sorted(z.namelist())!=['package.json','server.js'] or any(x.file_size>131072 for x in z.infolist()):raise SystemExit('Unexpected package structure')
 for name in z.namelist():
  data=z.read(name)
  if b'PRIVATE KEY' in data or b'BEGIN CERTIFICATE' in data:raise SystemExit('Certificate material is forbidden in fixture package')
fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o400)
with os.fdopen(fd,'wb') as f:f.write(b)
print('Reviewed snapshot SHA256 matched: '+sys.argv[3])
CHECK
az webapp deploy --subscription "$SUBSCRIPTION_ID" --resource-group "$RG" --name "$BACKEND" --type zip --src-path "$SNAPSHOT/origin.zip" --clean true --restart true --only-show-errors
printf 'Deployment returned. Inspect status; close SCM before publishing edge. Backend health remains separate evidence.\n'
