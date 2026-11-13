#!/usr/bin/env bash
# Designed, not tested. Static check, no Azure calls: the two region blocks and the on-premises block must not overlap.
# It only greps the example plan in main.tf and onprem.tf; whitespace tolerant.
set -euo pipefail
cd "$(dirname "$0")/.."
tr -s ' \t\n' ' ' < main.tf | grep -Eq 'block *= *"10\.20\.0\.0/15"' || { echo "FAIL: region A block missing"; exit 1; }
tr -s ' \t\n' ' ' < main.tf | grep -Eq 'block *= *"10\.22\.0\.0/15"' || { echo "FAIL: region B block missing"; exit 1; }
tr -s ' \t\n' ' ' < onprem.tf | grep -Eq 'address_space *= *\["10\.200\.0\.0/16"\]' || { echo "FAIL: on-premises block missing"; exit 1; }
echo "OK: 10.20.0.0/15, 10.22.0.0/15 and 10.200.0.0/16 are present and disjoint"
