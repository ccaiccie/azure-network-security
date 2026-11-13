#!/usr/bin/env bash
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_context
: "${1:?Supply a new private config filename}"
python3 - "$1" <<'WRITE'
import json,os,sys
from pathlib import Path
p=Path(sys.argv[1]);anc=[p.parent,*p.parents]
if p.exists() or p.is_symlink() or any(x.is_symlink() for x in anc):raise SystemExit('Refuse existing or symlink output path')
j=json.loads(os.environ['TF_OUTPUTS'])
keys=['edge_fqdn','origin_fqdn','gateway_public_ip','backend_fqdn','frontdoor_id','operator_cidr']
fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:json.dump({k:j[k]['value'] for k in keys},f,indent=2);f.write('\n')
WRITE
