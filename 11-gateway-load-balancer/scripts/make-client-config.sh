#!/usr/bin/env bash
# Local declared outputs only, no upload or network probe.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# == 1 ]] || { printf 'Usage: make-client-config.sh NEW_FILE\n' >&2; exit 2; }
load_context
python3 - "$TF_OUTPUTS" "$1" <<'CONFIG'
import ipaddress,json,os,sys
v={k:x['value'] for k,x in json.loads(sys.argv[1]).items()}
def valid(x):
 a=ipaddress.IPv4Address(x)
 return str(a)==x and a.is_global and not(a.is_multicast or a.is_reserved or a.is_unspecified) and a not in ipaddress.ip_network('192.88.99.0/24') and a not in ipaddress.ip_network('192.0.0.0/24')
c,p=v['client_public_ip'],v['consumer_public_ip']
if not valid(c) or not valid(p) or c==p:raise SystemExit('Require distinct actual global client C and consumer P')
config={'client_public_ip':c,'consumer_public_ip':p,'backend_ip':'10.20.1.20'}
fd=os.open(sys.argv[2],os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
with os.fdopen(fd,'w') as f:f.write(json.dumps(config,indent=2)+'\n');f.flush();os.fsync(f.fileno())
print('Wrote public config. Review and use only on the separately authorized external client; no upload/probe performed.')
CONFIG
