#!/usr/bin/env bash
# Local-only tests. No install, initialization, Azure login/requests or real plans.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for path in "$ROOT"/scripts/*.sh; do
  bash -n "$path"
  printf 'PASS bash syntax: %s\n' "$(basename "$path")"
done
python3 "$ROOT/tests/static-contract.py"
python3 "$ROOT/tests/test_local.py"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re,subprocess,sys
count=0
for path in Path(sys.argv[1]).glob('*.md'):
    for index,code in enumerate(re.findall(r'```bash\n(.*?)```',path.read_text(),re.S),1):
        result=subprocess.run(['bash','-n'],input=code,text=True,capture_output=True)
        if result.returncode:raise SystemExit(f'{path.name} Bash fence {index}: {result.stderr}')
        count+=1
print(f'PASS Markdown Bash syntax: {count} fences; no commands executed by this syntax-check step.')
PY
if command -v terraform >/dev/null 2>&1; then
  terraform -chdir="$ROOT" fmt -check -diff -recursive
  if [[ -d "$ROOT/.terraform/providers" ]]; then terraform -chdir="$ROOT" validate; fi
else
  printf 'NOT RUN terraform fmt/init/validate/test: Terraform unavailable.\n'
fi
