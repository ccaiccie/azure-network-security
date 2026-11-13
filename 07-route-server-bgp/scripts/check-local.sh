#!/usr/bin/env bash
# Offline source, shell, Python, fake-control/CLI and loopback tests ONLY.
# No provider initialization/download, cloud APIs, nft/sysctl or guest mutation.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
mkdir -p validation
python3 - "$ROOT" <<'PY' | tee validation/syntax-checks.txt
import ast,configparser,re,subprocess,sys,tempfile
from pathlib import Path
r=Path(sys.argv[1]);py=sh=units=fences=0
for p in sorted(r.rglob('*.py')):
 if '.terraform' in p.parts:continue
 ast.parse(p.read_text(),filename=str(p));py+=1
for p in sorted((r/'scripts').iterdir()):
 if p.is_file() and p.read_text().startswith('#!/usr/bin/env bash'):
  subprocess.run(['bash','-n',str(p)],check=True);sh+=1
for p in sorted(r.rglob('*.service')):
 c=configparser.ConfigParser(interpolation=None,strict=False);c.optionxform=str;c.read_string(p.read_text())
 assert c.has_section('Unit') and c.has_section('Service') and c.has_option('Service','ExecStart');units+=1
for p in sorted((r/'guest').glob('*.conf')):
 c=configparser.ConfigParser(interpolation=None,strict=False);c.optionxform=str;c.read_string(p.read_text())
 assert c.has_section('Unit') and c.has_option('Unit','Requires') and c.has_option('Unit','After');units+=1
for p in sorted(r.glob('*.md')):
 for block in re.findall(r'```bash\n(.*?)```',p.read_text(),re.S):
  subprocess.run(['bash','-n'],input=block,text=True,check=True);fences+=1
print(f'PASS Python AST={py}; Bash helpers={sh}; service INI structure={units}; Markdown Bash fences={fences}.')
print('No HCL parser, systemd semantic/service execution or nft syntax validation is implied.')
PY
python3 tests/source_contract.py | tee validation/source-checks.txt
python3 -m unittest discover -s tests -p 'test_*.py' -v > validation/local-tests.txt 2>&1 || { cat validation/local-tests.txt; exit 1; }
tail -5 validation/local-tests.txt
if command -v terraform >/dev/null 2>&1; then
  terraform fmt -check -recursive > validation/terraform-fmt.txt 2>&1
  # Validation needs an existing initialized provider cache. Never initialize here.
  if [[ -d .terraform/providers ]]; then
    terraform validate -no-color > validation/terraform-validate.txt 2>&1
  else
    printf 'NOT RUN: Terraform validate, provider cache absent. No init or download attempted.\n'
  fi
else
  printf 'NOT RUN: terraform fmt/init/validate/test; Terraform executable absent.\n'
fi
printf 'Never interpret these local checks as Azure/provider/guest/HA evidence.\n'
