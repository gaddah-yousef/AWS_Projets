#!/bin/bash
# =============================================================
# AWS Networking Lab - NAT Gateway
# =============================================================
set -euo pipefail

source /tmp/networking_ids.env

echo "=== [1/2] Elastic IP + NAT Gateway pour VPC-A ==="
EIP=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT=$(aws ec2 create-nat-gateway \
  --subnet-id $SUB_A_PUB \
  --allocation-id $EIP \
  --query 'NatGateway.NatGatewayId' --output text)
aws ec2 create-tags --resources $NAT --tags Key=Name,Value="NetworkLab-NAT"
echo "Attente NAT Gateway..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT
echo "NAT Gateway disponible : $NAT"

echo "=== [2/2] Route par défaut via NAT pour subnet privé ==="
aws ec2 create-route --route-table-id $RT_A_PRIV \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT
echo "Route 0.0.0.0/0 → NAT ajoutée"

echo ""
echo "=== NAT GATEWAY TERMINÉ ==="
echo "Les instances privées VPC-A ont maintenant accès Internet via NAT"
