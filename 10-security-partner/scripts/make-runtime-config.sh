#!/usr/bin/env bash
# Declared local Terraform outputs only. Public config; no upload or cloud request.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# == 2 && ( "$1" == app || "$1" == origin1 || "$1" == origin2 ) ]] || { printf 'Usage: make-runtime-config.sh app|origin1|origin2 NEW_FILE\n' >&2; exit 2; }
load_context
python3 - "$TF_OUTPUTS" "$1" "$2" <<'PY'
import ipaddress,json,os,sys
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()};role=sys.argv[2];ds=v['origin_public_ips'];pool=v['egress_public_ips']
def valid(x):
 a=ipaddress.IPv4Address(x)
 return str(a)==x and a.is_global and not(a.is_multicast or a.is_reserved or a.is_unspecified) and a not in ipaddress.ip_network('192.88.99.0/24') and a not in ipaddress.ip_network('192.0.0.0/24')
if not isinstance(ds,dict) or set(ds)!={'origin1','origin2'} or len(set(ds.values()))!=2 or any(not valid(d) for d in ds.values()):raise SystemExit('Require two distinct actual global public origin IPv4 addresses')
if not isinstance(pool,list) or not 1<=len(pool)<=16 or len(set(pool))!=len(pool) or any(not valid(e) or e in ds.values() for e in pool):raise SystemExit('Require complete unique approved global E pool, max16, disjoint both D')
ips={'app':'10.10.1.10','origin1':'10.30.1.20','origin2':'10.30.1.21'}
config={'role':role,'private_ip':ips[role],'app_ip':ips['app'],'origins':{k:{'private_ip':ips[k],'public_ip':ds[k]} for k in ['origin1','origin2']},'egress_public_ips':pool}
fd=os.open(sys.argv[3],os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
with os.fdopen(fd,'w') as f:f.write(json.dumps(config,indent=2)+'\n');f.flush();os.fsync(f.fileno())
print('Wrote public config only; review/copy to intended lab host separately:',sys.argv[3])
PY
