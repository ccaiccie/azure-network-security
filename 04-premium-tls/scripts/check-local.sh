#!/usr/bin/env bash
# Local source/mocks/loopback only. Never invokes Azure, deployment or Terraform init/apply.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for file in scripts/*.sh; do bash -n "$file"; done
python3 - <<'PY'
from pathlib import Path
import ast,re,subprocess
for p in [*Path('scripts').glob('*.py'),*Path('tests').glob('*.py')]:ast.parse(p.read_text(),filename=str(p))
n=0
for p in Path('.').rglob('*.md'):
    for code in re.findall(r'```bash\n(.*?)```',p.read_text(),re.S):
        subprocess.run(['bash','-n'],input=code,text=True,check=True);n+=1
print(f'Markdown Bash fences parsed: {n}')
PY
python3 tests/source_contract.py
node --check origin/server.js
node --test tests/test_origin.cjs
python3 tests/test_helpers.py
if command -v terraform >/dev/null; then
  terraform fmt -check -recursive
  if [[ -d .terraform/providers ]]; then terraform validate; else printf 'Terraform validate NOT RUN: provider not initialized.\n'; fi
else
  printf 'Terraform fmt/init/validate/mock plans NOT RUN: executable unavailable.\n'
fi
printf 'Local checks completed. No Azure, actual TLS or CA/key operation was performed.\n'
