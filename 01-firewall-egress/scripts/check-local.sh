#!/usr/bin/env bash
# Local-only checks. Does not install tools, initialize providers, authenticate or call Azure.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for script in "$ROOT"/scripts/*.sh; do
  bash -n "$script"
  printf 'PASS bash syntax: %s\n' "$(basename "$script")"
done
python3 "$ROOT/tests/static-contract.py"
python3 "$ROOT/tests/test_guest_harness.py"
if command -v terraform >/dev/null 2>&1; then
  terraform -chdir="$ROOT" fmt -check -diff -recursive
  if [[ -d "$ROOT/.terraform/providers" ]]; then
    terraform -chdir="$ROOT" validate
  else
    printf 'NOT RUN terraform validate: no initialized provider directory.\n'
  fi
else
  printf 'NOT RUN terraform fmt/init/validate: Terraform executable unavailable.\n'
fi
