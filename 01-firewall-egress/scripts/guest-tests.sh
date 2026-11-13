#!/usr/bin/env bash
# Operator-run INSIDE the spoke VM. Installed by cloud-init, never auto-executed.
# This collects observations; only route + NSG + firewall logs establish a verdict.
set -u -o pipefail
umask 077

for tool in python3 curl getent ip date; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'BLOCKED: required preinstalled tool missing: %s\n' "$tool" >&2
    printf 'Do not broaden firewall rules automatically to install packages.\n' >&2
    exit 2
  fi
done

CONFIG=${EGRESS_DEMO_CONFIG:-/etc/egress-demo.json}
if [[ ! -r "$CONFIG" ]]; then
  printf 'BLOCKED: %s not readable. Check cloud-init or use the manual runbook.\n' "$CONFIG" >&2
  exit 2
fi

if ! CONFIG_LINES=$(python3 - "$CONFIG" <<'PY'
import json, sys
config = json.load(open(sys.argv[1], encoding="utf-8"))
for key in ("firewall_private_ip", "firewall_public_ip", "vm_private_ip", "policy_mode"):
    print(config[key])
print(" ".join(config["allowed_fqdns"]))
PY
); then
  printf 'BLOCKED: invalid lab configuration.\n' >&2
  exit 2
fi
mapfile -t SETTINGS <<< "$CONFIG_LINES"
F=${SETTINGS[0]}
P=${SETTINGS[1]}
VM_IP=${SETTINGS[2]}
MODE=${SETTINGS[3]}
read -r -a ALLOWED <<< "${SETTINGS[4]}"
PRIMARY_HOST=${PRIMARY_HOST:-www.microsoft.com}
ECHO_HOST=${ECHO_HOST:-api.ipify.org}
UNLISTED_HOST=${UNLISTED_HOST:-www.bing.com}

# Only an explicitly named lab destination is used as the positive host.
if [[ " ${ALLOWED[*]} " != *" $PRIMARY_HOST "* ]]; then
  printf 'Set PRIMARY_HOST to an allowed hostname; %s is not configured.\n' "$PRIMARY_HOST" >&2
  exit 2
fi
for host in "$PRIMARY_HOST" "$ECHO_HOST" "$UNLISTED_HOST"; do
  if [[ ! "$host" =~ ^[a-z0-9][a-z0-9.-]+[a-z0-9]$ ]]; then
    printf 'BLOCKED: use plain lowercase hostnames without URLs/options.\n' >&2
    exit 2
  fi
done
if ! ip -4 -o addr show | grep -Fq " $VM_IP/"; then
  printf 'BLOCKED: this machine does not own expected VM address %s. Run inside the spoke VM.\n' "$VM_IP" >&2
  exit 2
fi

OUT=${1:-"$HOME/egress-evidence-$(date -u +%Y%m%dT%H%M%SZ)"}
mkdir -p "$OUT"
exec > >(tee "$OUT/session.txt") 2>&1
printf 'UTC start: %s\nPolicy mode: %s\nVM: %s\nFirewall private: %s\nFirewall public: %s\n' \
  "$(date -u +%FT%TZ)" "$MODE" "$VM_IP" "$F" "$P"
printf 'Allowed DNS names: %s\n\n' "${ALLOWED[*]}"
ip -4 -brief address
ip -4 route
cat /etc/resolv.conf
if command -v resolvectl >/dev/null 2>&1; then
  resolvectl status || true
fi

for host in "$PRIMARY_HOST" "$ECHO_HOST" "$UNLISTED_HOST"; do
  printf '\nDNS A observations for %s at %s\n' "$host" "$(date -u +%FT%TZ)"
  getent ahostsv4 "$host" | tee "$OUT/dns-$host.txt" || true
done

probe() {
  local name=$1 url=$2 rc
  printf '\nCASE %s UTC %s URL %s\n' "$name" "$(date -u +%FT%TZ)" "$url"
  curl -q -4 --http1.1 --noproxy '*' --connect-timeout 5 --max-time 20 \
    --silent --show-error --verbose --dump-header "$OUT/$name.headers" \
    --output "$OUT/$name.body" \
    --write-out 'http_code=%{http_code} remote_ip=%{remote_ip} remote_port=%{remote_port} local_ip=%{local_ip} local_port=%{local_port} time_total=%{time_total}\n' \
    "$url" 2>"$OUT/$name.stderr"
  rc=$?
  printf 'curl_exit=%s\n' "$rc" | tee "$OUT/$name.exit"
  sed -n '1,20p' "$OUT/$name.headers" 2>/dev/null || true
  tail -n 12 "$OUT/$name.stderr"
  # -q is the first curl option: ignore .curlrc. No --location, --insecure,
  # proxy, HTTP/3, or reused connection between cases.
}

probe allowed-https "https://$PRIMARY_HOST/"
if [[ " ${ALLOWED[*]} " == *" $ECHO_HOST "* ]]; then
  probe egress-ip "https://$ECHO_HOST/"
  # The default api.ipify.org endpoint returns plain-text public IPv4.
  OBSERVED=$(tr -d '\r\n' < "$OUT/egress-ip.body" 2>/dev/null || true)
  if [[ "$OBSERVED" == "$P" ]]; then
    printf 'Public-IP observation MATCHES configured firewall public IP: %s\n' "$P"
  else
    printf 'Public-IP observation DOES NOT MATCH. Expected %s; inspect egress-ip.body and logs.\n' "$P"
  fi
else
  printf '\nSKIPPED echo: %s is not allowed. Use approved server-side source-IP evidence.\n' "$ECHO_HOST"
fi

probe http-negative "http://$PRIMARY_HOST/"
if [[ " ${ALLOWED[*]} " != *" $UNLISTED_HOST "* ]]; then
  probe unlisted-https "https://$UNLISTED_HOST/"
else
  printf '\nSKIPPED unlisted-host test: %s is in the allowlist.\n' "$UNLISTED_HOST"
fi

dns_probe() {
  local name=$1 rc
  shift
  printf '\nDNS CASE %s UTC %s\n' "$name" "$(date -u +%FT%TZ)"
  dig "$@"
  rc=$?
  printf 'dig_exit=%s\n' "$rc"
}

if command -v dig >/dev/null 2>&1; then
  printf '\nDNS proxy and direct platform DNS probes (direct denial expected):\n'
  dns_probe proxy-udp @"$F" "$PRIMARY_HOST" A +time=3 +tries=1
  dns_probe proxy-tcp @"$F" "$PRIMARY_HOST" A +tcp +time=3 +tries=1
  dns_probe direct-platform-udp @168.63.129.16 "$PRIMARY_HOST" A +time=3 +tries=1
  dns_probe direct-platform-tcp @168.63.129.16 "$PRIMARY_HOST" A +tcp +time=3 +tries=1
  printf 'DNS_BYPASS_VERDICT=NEEDS_REVIEW: correlate both direct-query outcomes with effective NSG policy.\n'
else
  printf '\nSKIPPED explicit DNS transport checks: dig is not preinstalled.\n'
  printf 'DNS_BYPASS_VERDICT=NOT_RUN: no DNS-bypass-prevention result can be claimed.\n'
fi

printf '\nUTC end: %s\nEvidence directory: %s\n' "$(date -u +%FT%TZ)" "$OUT"
printf 'No case is declared passed by this script. Correlate effective routes, NSGs and firewall logs.\n'
if [[ "$MODE" == network ]]; then
  printf 'Network FQDN rules allow resolved IPs. An unlisted hostname can share an allowed IP and succeed.\n'
  printf 'The TCP80 case is the definitive firewall-port negative; require its Deny log.\n'
fi
