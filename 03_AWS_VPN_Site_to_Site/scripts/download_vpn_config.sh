#!/usr/bin/env bash
# Download existing AWS VPN customer configuration to a private local file.
# Contains sensitive VPN configuration: do NOT commit the resulting file.
set -euo pipefail
umask 077
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
: "${VPN_ID:?Export VPN_ID, e.g. vpn-0123456789abcdef0}"
OUT="${OUTPUT_FILE:-vpn_customer_${VPN_ID}.xml}"
[[ ! -e "$OUT" ]] || { echo "File exists: $OUT (choose a new OUTPUT_FILE)" >&2; exit 1; }
aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID"   --query 'VpnConnections[0].CustomerGatewayConfiguration' --output text > "$OUT"
[[ -s "$OUT" ]] || { rm -f "$OUT"; echo "No configuration downloaded." >&2; exit 1; }
chmod 600 "$OUT"
echo "Saved sensitive customer configuration to $OUT (permissions 600)."
echo "Never commit this file, and configure both on-prem tunnels separately."
