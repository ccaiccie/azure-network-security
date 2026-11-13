#!/usr/bin/env bash
# Backend-local health only. No proxy/DNS override on any client test, no installation.
set -euo pipefail
exec python3 - "${POLICY_LAB_CONFIG:-/etc/azure-policy-lab.json}" <<'PY'
import json,subprocess,sys,time
from datetime import datetime,timezone
from urllib.request import ProxyHandler,Request,build_opener
with open(sys.argv[1]) as config_file:c=json.load(config_file)
address=c['private_ip']
assert c['role']=='backend' and address=='10.20.1.10'
ips=subprocess.run(['ip','-4','-o','addr','show'],check=True,text=True,capture_output=True).stdout
assert f' {address}/' in ips,'Wrong VM'
print('UTC',datetime.now(timezone.utc).isoformat(),flush=True)
print(subprocess.run(['ss','-lnt'],check=True,text=True,capture_output=True).stdout)
opener=build_opener(ProxyHandler({}))
for port in (8080,8081):
    service=f'azure-policy-fixture@{port}.service'
    result=subprocess.run(['systemctl','is-active',service],capture_output=True,text=True)
    print(service,result.stdout.strip(),flush=True)
    if result.returncode:raise SystemExit('NOT READY: inactive '+service)
    for name in ('allowed.policy.test','denied.policy.test'):
        case=f'local-{name.split(".")[0]}-{port}-{time.time_ns()}'
        request=Request(f'http://{address}:{port}/probe',headers={'Host':f'{name}:{port}','X-Lab-Case-ID':case,'User-Agent':f'azure-policy-lab/{case}'})
        error=None
        for attempt in range(10):
            try:
                with opener.open(request,timeout=2) as response:
                    row=json.load(response);assert response.status==200
                assert (row.get('fixture'),row.get('host'),row.get('case_id'),row.get('server_ip'),row.get('server_port'),row.get('peer_ip'))==('azure-policy-origin-v1',f'{name}:{port}',case,address,port,address)
                print(json.dumps(row,sort_keys=True),flush=True);error=None;break
            except (OSError,ValueError,AssertionError) as exc:error=exc;time.sleep(1)
        if error is not None:raise SystemExit(f'NOT READY {name}:{port}: {error}')
print('LOCAL_FIXTURES_READY: both names and both listeners on B only; no firewall outcome inferred')
PY
