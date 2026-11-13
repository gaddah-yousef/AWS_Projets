#!/bin/bash
# =============================================================
# AWS VPN Site-to-Site - Setup complet
# Crée: VGW, CGW, VPN Connection, routes et monitoring
# =============================================================
set -euo pipefail
umask 077
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

REGION="$AWS_DEFAULT_REGION"
: "${CUSTOMER_IP:?Export CUSTOMER_IP (public IP of your authorized on-prem gateway)}"
CUSTOMER_ASN="${CUSTOMER_ASN:-65000}"
AWS_ASN="64512"
ONPREM_CIDR="${ONPREM_CIDR:-192.168.0.0/24}"
 : "${VPC_ID:?Export VPC_ID for your own VPC}"
: "${PRIV_RT_ID:?Export PRIV_RT_ID for its private route table}"
aws ec2 describe-vpcs --vpc-ids "$VPC_ID" >/dev/null
aws ec2 describe-route-tables --route-table-ids "$PRIV_RT_ID" >/dev/null
echo "AWS account $(aws sts get-caller-identity --query Account --output text), region $REGION"
read -r -p "Site-to-Site VPN incurs hourly charges. Type CREATE: " CONSENT
[[ "$CONSENT" == "CREATE" ]] || { echo "Cancelled."; exit 1; }

echo "=== [1/6] Virtual Private Gateway ==="
VGW=$(aws ec2 create-vpn-gateway \
  --type ipsec.1 \
  --amazon-side-asn $AWS_ASN \
  --query 'VpnGateway.VpnGatewayId' --output text)
aws ec2 create-tags --resources $VGW --tags Key=Name,Value="Lab-VGW"
aws ec2 attach-vpn-gateway --vpn-gateway-id $VGW --vpc-id $VPC_ID
echo "VGW : $VGW (attaché au VPC $VPC_ID)"

echo "Attente propagation VGW..."
sleep 15

echo "=== [2/6] Customer Gateway ==="
CGW=$(aws ec2 create-customer-gateway \
  --type ipsec.1 \
  --public-ip $CUSTOMER_IP \
  --bgp-asn $CUSTOMER_ASN \
  --query 'CustomerGateway.CustomerGatewayId' --output text)
aws ec2 create-tags --resources $CGW --tags Key=Name,Value="Lab-CGW-OnPrem"
echo "CGW : $CGW (IP: $CUSTOMER_IP)"

echo "=== [3/6] VPN Connection (2 tunnels redondants) ==="
VPN_ID=$(aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id $CGW \
  --vpn-gateway-id $VGW \
  --options '{
    "StaticRoutesOnly": true,
    "TunnelOptions": [
      {
        "TunnelInsideCidr": "169.254.10.0/30",
        "Phase1EncryptionAlgorithms": [{"Value": "AES256"}],
        "Phase2EncryptionAlgorithms": [{"Value": "AES256-GCM-16"}],
        "Phase1IntegrityAlgorithms": [{"Value": "SHA2-256"}],
        "Phase2IntegrityAlgorithms": [{"Value": "SHA2-256"}],
        "Phase1DHGroupNumbers": [{"Value": 14}],
        "Phase2DHGroupNumbers": [{"Value": 14}],
        "IKEVersions": [{"Value": "ikev2"}]
      },
      {
        "TunnelInsideCidr": "169.254.11.0/30",
        "Phase1EncryptionAlgorithms": [{"Value": "AES256"}],
        "Phase2EncryptionAlgorithms": [{"Value": "AES256-GCM-16"}],
        "Phase1IntegrityAlgorithms": [{"Value": "SHA2-256"}],
        "Phase2IntegrityAlgorithms": [{"Value": "SHA2-256"}],
        "Phase1DHGroupNumbers": [{"Value": 14}],
        "Phase2DHGroupNumbers": [{"Value": 14}],
        "IKEVersions": [{"Value": "ikev2"}]
      }
    ]
  }' \
  --query 'VpnConnection.VpnConnectionId' --output text)
aws ec2 create-tags --resources $VPN_ID --tags Key=Name,Value="Lab-VPN-SiteToSite"
echo "VPN Connection : $VPN_ID"

echo "=== [4/6] Route statique vers on-premise ==="
aws ec2 create-vpn-connection-route \
  --vpn-connection-id $VPN_ID \
  --destination-cidr-block $ONPREM_CIDR
echo "Route $ONPREM_CIDR ajoutée à la VPN connection"

echo "=== [5/6] Route Propagation dans la route table privée ==="
aws ec2 enable-vgw-route-propagation \
  --route-table-id $PRIV_RT_ID \
  --gateway-id $VGW
echo "Route propagation activée"

echo "=== [6/6] Download config pour équipement on-premise ==="
aws ec2 describe-vpn-connections \
  --vpn-connection-ids $VPN_ID \
  --query 'VpnConnections[0].CustomerGatewayConfiguration' \
  --output text > "./vpn_customer_${VPN_ID}.xml"
chmod 600 "./vpn_customer_${VPN_ID}.xml"
echo "Configuration XML sensible sauvegardée : ./vpn_customer_${VPN_ID}.xml (chmod 600)"
echo "(Importer dans Cisco/Fortinet/pfSense/StrongSwan)"

echo ""
echo "=== VPN SETUP TERMINÉ ==="
echo "VGW: $VGW | CGW: $CGW | VPN: $VPN_ID"
echo "Les tunnels seront UP quand le routeur on-prem sera configuré"
echo ""
echo "Pour vérifier l'état des tunnels:"
echo "  aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID \\"
echo "    --query 'VpnConnections[0].VgwTelemetry'"
