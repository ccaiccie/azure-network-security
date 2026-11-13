#!/usr/bin/env bash
# Local source, mocked helpers and loopback HTTP only. No Azure or Terraform apply.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for file in scripts/*.sh; do bash -n "$file"; done
python3 - <<'PY'
from pathlib import Path
import ast,configparser,re,subprocess
for p in [*Path('scripts').glob('*.py'),*Path('tests').glob('*.py'),*Path('fixtures').glob('*.py')]:ast.parse(p.read_text(),filename=str(p))
n=0
for p in Path('.').rglob('*.md'):
    for block in re.findall(r'```bash\n(.*?)```',p.read_text(),re.S):subprocess.run(['bash','-n'],input=block,text=True,check=True);n+=1
print(f'Markdown Bash fences parsed: {n}')
unit=configparser.RawConfigParser();unit.read('fixtures/azure-policy-fixture@.service')
assert unit['Service']['ExecStart']=='/usr/bin/python3 -I /opt/azure-policy-lab/server.py --bind ${BIND_IP} --port %i'
assert unit['Service']['DynamicUser']=='yes' and unit['Service']['ProtectSystem']=='strict'
print('Systemd unit INI/source checks passed; no service loaded or started.')
PY
python3 tests/source_contract.py
python3 tests/test_local.py
if command -v terraform >/dev/null; then
  terraform fmt -check -recursive
  if [[ -d .terraform/providers ]]; then terraform validate; else printf 'Terraform validate NOT RUN: provider uninitialized.\n'; fi
else
  printf 'Terraform fmt/init/validate/mock plans NOT RUN: executable unavailable.\n'
fi
printf 'Local checks complete. No Azure DNS, routes, policy decisions or runtime were validated.\n'
