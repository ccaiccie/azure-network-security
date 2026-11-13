#!/usr/bin/env bash
# Local-only. Unit tests use loopback ports 8080/8081 and fake control-plane tools.
# Never downloads/installs tools, authenticates, calls Azure, or executes Terraform plans.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for path in "$ROOT"/scripts/*.sh; do
  bash -n "$path"
  printf 'PASS bash syntax: %s\n' "$(basename "$path")"
done
python3 "$ROOT/tests/static-contract.py"
python3 "$ROOT/tests/test_local.py"
if command -v terraform >/dev/null 2>&1; then
  terraform -chdir="$ROOT" fmt -check -diff -recursive
  if [[ -d "$ROOT/.terraform/providers" ]]; then terraform -chdir="$ROOT" validate; fi
else
  printf 'NOT RUN terraform fmt/init/validate/test: Terraform unavailable.\n'
fi
