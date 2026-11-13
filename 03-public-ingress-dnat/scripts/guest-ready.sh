#!/usr/bin/env bash
# Inside the backend only. No install, external requests or firewall verdict.
set -euo pipefail
exec python3 - "${DNAT_LAB_CONFIG:-/etc/azure-dnat-lab.json}" <<'PY'
import json, subprocess, sys, time
from datetime import datetime, timezone
from urllib.request import ProxyHandler, build_opener
c=json.load(open(sys.argv[1],encoding='utf-8'))
address,port,role=c['private_ip'],c['port'],c['role']
if role!='backend' or port!=8080: raise SystemExit('Invalid fixture role or port')
print('Readiness UTC',datetime.now(timezone.utc).isoformat(),flush=True)
addresses=subprocess.run(['ip','-4','-o','addr','show'],check=True,text=True,capture_output=True).stdout
if f' {address}/' not in addresses: raise SystemExit('Wrong backend machine')
print(subprocess.run(['ss','-lnt'],check=True,text=True,capture_output=True).stdout)
service=subprocess.run(['systemctl','is-active','azure-dnat-fixture.service'],text=True,capture_output=True)
print(service.stdout,service.stderr,flush=True)
if service.returncode: raise SystemExit('NOT READY: owned fixture service is not active')
opener=build_opener(ProxyHandler({}))
error=None
for attempt in range(10):
    try:
        with opener.open(f'http://{address}:8080/ready-local',timeout=2) as response:
            record=json.load(response)
            if response.status!=200: raise ValueError('Expected HTTP200')
        if (record.get('fixture_role'),record.get('server_ip'),record.get('server_port'),record.get('peer_ip')) != (role,address,port,address):
            raise ValueError('Wrong local fixture identity')
        print(json.dumps(record,sort_keys=True),flush=True)
        error=None
        break
    except (OSError,ValueError) as exc:
        error=exc
        time.sleep(1)
if error is not None: raise SystemExit(f'NOT READY: {error}')
print('LOCAL_FIXTURE_READY: local only, not public DNAT verification')
PY
