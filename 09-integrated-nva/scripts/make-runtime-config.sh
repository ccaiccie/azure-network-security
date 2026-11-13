#!/usr/bin/env bash
# Local Terraform declared outputs only. Writes PUBLIC address config; uploads nothing.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# == 2 && ( "$1" == app || "$1" == origin ) ]] || { printf 'Usage: make-runtime-config.sh app|origin NEW_FILE\n' >&2; exit 2; }
load_context
python3 - "$TF_OUTPUTS" "$1" "$2" <<'PY'
import ipaddress,json,os,sys
from pathlib import Path
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()};role=sys.argv[2]
d=v['origin_public_ip'];pool=v['egress_public_ips']
def valid(x):
 a=ipaddress.IPv4Address(x)
 return str(a)==x and a.is_global and not(a.is_multicast or a.is_reserved or a.is_unspecified) and a not in ipaddress.ip_network('192.88.99.0/24') and a not in ipaddress.ip_network('192.0.0.0/24')
if not valid(d) or not isinstance(pool,list) or not 1<=len(pool)<=16 or len(set(pool))!=len(pool) or any(not valid(x) or x==d for x in pool):raise SystemExit('Require actual globally routable D and complete unique E pool distinct from D')
config={'role':role,'private_ip':'10.10.1.10' if role=='app' else '10.30.1.20','app_ip':'10.10.1.10','origin_ip':'10.30.1.20','origin_public_ip':d,'egress_public_ips':pool}
path=Path(sys.argv[3]);fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
with os.fdopen(fd,'w') as f:f.write(json.dumps(config,indent=2)+'\n');f.flush();os.fsync(f.fileno())
print('Wrote public runtime config; independently copy only to intended lab VM after review:',path)
PY
