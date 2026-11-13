#!/usr/bin/env bash
# Designed, not tested. Runs ON an NVA as root. Reads /etc/frr/lab.env and writes /etc/frr/frr.conf, then restarts FRR.
# Installed by frr-setup.sh.tftpl as /usr/local/bin/frr-render.sh and called by frr-policy.sh after every change.
set -euo pipefail
. /etc/frr/lab.env

# Variables in lab.env:
#   HOSTNAME ASN ROUTER_ID RS_IPS              set once at boot
#   ANNOUNCE   prefixes to originate           (default "10.99.0.0/24")
#   PREPEND    how many extra copies of our ASN to add on the way out (0 = none)
#   LOCALPREF  local preference set on routes received (0 = leave default 100)
#   MED        metric set on routes sent (0 = none)
#   COMMUNITY  a community such as 65001:100 added to routes sent (empty = none)
#   AGGREGATE  an aggregate with summary-only, for example 10.99.0.0/16 (empty = none)
#   FILTER     a prefix list, "prefix[,prefix]" that may be sent (empty = send everything we originate)
ANNOUNCE="${ANNOUNCE:-10.99.0.0/24}"; PREPEND="${PREPEND:-0}"; LOCALPREF="${LOCALPREF:-0}"
MED="${MED:-0}"; COMMUNITY="${COMMUNITY:-}"; AGGREGATE="${AGGREGATE:-}"; FILTER="${FILTER:-}"

{
  echo "frr defaults traditional"
  echo "hostname $HOSTNAME"
  echo "service integrated-vtysh-config"
  echo "!"
  for p in $ANNOUNCE; do echo "ip route $p blackhole"; done
  echo "!"
  if [ -n "$FILTER" ]; then
    i=10
    for p in $(echo "$FILTER" | tr ',' ' '); do echo "ip prefix-list ALLOW-OUT seq $i permit $p"; i=$((i + 10)); done
    echo "!"
  fi
  echo "route-map TO-RS permit 10"
  [ -n "$FILTER" ] && echo " match ip address prefix-list ALLOW-OUT"
  if [ "$PREPEND" -gt 0 ]; then
    pp=""; n=0
    while [ "$n" -lt "$PREPEND" ]; do pp="$pp $ASN"; n=$((n + 1)); done
    echo " set as-path prepend$pp"
  fi
  [ "$MED" -gt 0 ] && echo " set metric $MED"
  [ -n "$COMMUNITY" ] && echo " set community $COMMUNITY additive"
  echo "!"
  echo "route-map FROM-RS permit 10"
  [ "$LOCALPREF" -gt 0 ] && echo " set local-preference $LOCALPREF"
  echo "!"
  echo "router bgp $ASN"
  echo " bgp router-id $ROUTER_ID"
  echo " no bgp ebgp-requires-policy"
  for r in $RS_IPS; do
    echo " neighbor $r remote-as 65515"
    echo " neighbor $r ebgp-multihop 255"
  done
  echo " address-family ipv4 unicast"
  for p in $ANNOUNCE; do echo "  network $p"; done
  [ -n "$AGGREGATE" ] && echo "  aggregate-address $AGGREGATE summary-only"
  for r in $RS_IPS; do
    echo "  neighbor $r route-map TO-RS out"
    echo "  neighbor $r route-map FROM-RS in"
  done
  echo " exit-address-family"
  echo "!"
} > /etc/frr/frr.conf
chown frr:frr /etc/frr/frr.conf
systemctl restart frr
