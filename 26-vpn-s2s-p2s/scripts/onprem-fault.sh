#!/usr/bin/env bash
# Designed, not tested. Runs ON vm-edge as root. Injects one fault for a break/fix drill, or removes it.
#   onprem-fault.sh ts-narrow       narrow the IPsec traffic selectors to 10.70.0.0/24 (the "tunnel up, no traffic" drill)
#   onprem-fault.sh apipa-mismatch  use 169.254.21.3 as the BGP source address instead of 169.254.21.2 (the BGP drill)
#   onprem-fault.sh mtu-blackhole   drop ICMP "fragmentation needed" and remove the MSS clamp (the MTU black hole drill)
#   onprem-fault.sh reset           undo all three
set -euo pipefail
CONF=/etc/swanctl/conf.d/vpn26.conf

# Point every configured BGP neighbour at a different local source address.
set_bgp_source() {
  local src="$1" peers p
  peers=$(vtysh -c 'show running-config' | awk '/^ neighbor .* remote-as/{print $2}')
  for p in $peers; do
    vtysh -c "configure terminal" -c "router bgp $(vtysh -c 'show running-config' | awk '/^router bgp/{print $3}')" \
      -c "neighbor $p update-source $src" > /dev/null
  done
}

case "${1:-}" in
  ts-narrow)
    cp -n "$CONF" "$CONF.orig"
    sed -i 's#local_ts = 0.0.0.0/0#local_ts = 10.70.0.0/24#; s#remote_ts = 0.0.0.0/0#remote_ts = 10.60.0.0/16#' "$CONF"
    swanctl --load-all
    ;;
  apipa-mismatch)
    ip addr add 169.254.21.3/32 dev lo 2>/dev/null || true
    set_bgp_source 169.254.21.3
    ;;
  mtu-blackhole)
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -o xfrm+ -j TCPMSS --set-mss 1350 2>/dev/null || true
    iptables -C OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP 2>/dev/null \
      || iptables -I OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP
    ;;
  reset)
    [ -f "$CONF.orig" ] && cp "$CONF.orig" "$CONF" && swanctl --load-all
    set_bgp_source 169.254.21.2 2>/dev/null || true
    ip addr del 169.254.21.3/32 dev lo 2>/dev/null || true
    iptables -D OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP 2>/dev/null || true
    /usr/local/sbin/vpn26-net.sh
    ;;
  *) echo "usage: $0 ts-narrow|apipa-mismatch|mtu-blackhole|reset"; exit 1 ;;
esac
