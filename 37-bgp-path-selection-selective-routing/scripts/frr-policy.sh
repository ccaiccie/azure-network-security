#!/usr/bin/env bash
# Designed, not tested. Runs ON an NVA as root (for example through az vm run-command). Changes BGP attributes and re-renders FRR.
# Usage: frr-policy.sh key=value [key=value ...]     keys: announce prepend localpref med community aggregate filter
#        frr-policy.sh reset                         back to the baseline (announce 10.99.0.0/24, no policy)
#        frr-policy.sh show                          prints the BGP table and what is advertised
# Examples: frr-policy.sh prepend=3
#           frr-policy.sh announce="10.99.0.0/24 10.99.0.0/25" community=65001:100
#           frr-policy.sh announce="10.99.0.0/24 10.99.1.0/24" aggregate=10.99.0.0/16
#           frr-policy.sh announce="10.99.0.0/24 10.99.0.0/25" filter=10.99.0.0/24
set -euo pipefail
ENVF=/etc/frr/lab.env

setvar() { # key value
  local k="$1" v="$2"
  grep -v "^$k=" "$ENVF" > "$ENVF.new" || true
  printf '%s="%s"\n' "$k" "$v" >> "$ENVF.new"
  mv "$ENVF.new" "$ENVF"
}

case "${1:-}" in
  show)
    vtysh -c "show ip bgp summary"
    vtysh -c "show ip bgp"
    for r in $(vtysh -c "show ip bgp summary" | awk '/^10\./{print $1}'); do
      echo "== advertised to $r"; vtysh -c "show ip bgp neighbors $r advertised-routes"
    done
    exit 0 ;;
  reset)
    setvar ANNOUNCE "10.99.0.0/24"; setvar PREPEND 0; setvar LOCALPREF 0; setvar MED 0
    setvar COMMUNITY ""; setvar AGGREGATE ""; setvar FILTER "" ;;
  "")
    echo "usage: $0 key=value ... | reset | show"; exit 1 ;;
  *)
    for kv in "$@"; do
      key="${kv%%=*}"; val="${kv#*=}"
      case "$key" in
        announce)  setvar ANNOUNCE "$val" ;;
        prepend)   setvar PREPEND "$val" ;;
        localpref) setvar LOCALPREF "$val" ;;
        med)       setvar MED "$val" ;;
        community) setvar COMMUNITY "$val" ;;
        aggregate) setvar AGGREGATE "$val" ;;
        filter)    setvar FILTER "$val" ;;
        *) echo "unknown key $key"; exit 1 ;;
      esac
    done ;;
esac
/usr/local/bin/frr-render.sh
sleep 5
vtysh -c "show ip bgp summary"
