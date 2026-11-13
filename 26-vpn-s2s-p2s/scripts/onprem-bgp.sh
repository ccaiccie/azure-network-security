#!/usr/bin/env bash
# Designed, not tested. Runs ON vm-edge (for example through az vm run-command) as root.
# Configures FRR so the simulated device speaks BGP over the XFRM interfaces. Run it again to change the setup.
#   onprem-bgp.sh apipa  [AZURE_ASN] [ONPREM_ASN]   peers 169.254.21.1 (and 169.254.22.1) from 169.254.21.2
#   onprem-bgp.sh plain  AZURE_BGP_IP1 [AZURE_BGP_IP2] [AZURE_ASN] [ONPREM_ASN]   peers the gateway's VNet address(es) from 10.70.255.1
#   onprem-bgp.sh off                                 removes BGP
# Set ONPREM_LOCAL_IP to override the local APIPA address (the mismatch drill in Break/fix 2 uses this).
set -euo pipefail

mode="${1:-}"
LAN_PREFIX="${LAN_PREFIX:-10.70.2.0/24}"
case "$mode" in
  apipa)
    AZ_ASN="${2:-65010}"; ON_ASN="${3:-65020}"
    LOCAL="${ONPREM_LOCAL_IP:-169.254.21.2}"
    PEERS="169.254.21.1 169.254.22.1"
    ;;
  plain)
    AZ_ASN="${4:-65010}"; ON_ASN="${5:-65020}"
    LOCAL="10.70.255.1"
    PEERS="${2:?azure bgp ip 1}${3:+ $3}"
    ;;
  off)
    vtysh -c "configure terminal" -c "no router bgp $(vtysh -c 'show running-config' | awk '/^router bgp/{print $3}')" || true
    exit 0
    ;;
  *) echo "usage: $0 apipa|plain|off ..."; exit 1 ;;
esac

# The BGP source address lives on the loopback; each Azure peer address is reached through its own XFRM interface.
ip addr add "$LOCAL/32" dev lo 2>/dev/null || true
i=0
for p in $PEERS; do
  ip route replace "$p/32" dev "xfrm$i"
  i=$((i + 1))
done

{
  echo "configure terminal"
  echo "router bgp $ON_ASN"
  echo " bgp router-id 10.70.255.1"
  echo " no bgp ebgp-requires-policy"
  for p in $PEERS; do
    echo " neighbor $p remote-as $AZ_ASN"
    echo " neighbor $p ebgp-multihop 8"
    echo " neighbor $p update-source $LOCAL"
  done
  echo " address-family ipv4 unicast"
  echo "  network $LAN_PREFIX"
  echo " exit-address-family"
  echo "end"
  echo "write memory"
} | vtysh
vtysh -c "show ip bgp summary"
