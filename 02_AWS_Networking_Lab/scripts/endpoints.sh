#!/bin/bash
# =============================================================
# AWS Networking Lab - VPC Endpoints (S3 Gateway + SSM Interface)
# Permet accès S3 et SSM sans passer par Internet
# =============================================================
set -euo pipefail

source /tmp/networking_ids.env

REGION="us-east-1"

echo "=== [1/4] VPC Endpoint S3 (Gateway - gratuit) ==="
# Gateway endpoint pour S3 - s'ajoute à la route table, pas de coût
EP_S3=$(aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_A \
  --service-name com.amazonaws.${REGION}.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids $RT_A_PRIV \
  --query 'VpcEndpoint.VpcEndpointId' --output text)
aws ec2 create-tags --resources $EP_S3 --tags Key=Name,Value="NetworkLab-EP-S3"
echo "S3 Endpoint (Gateway) : $EP_S3"

echo "=== [2/4] Security Group pour Interface Endpoints ==="
SG_EP=$(aws ec2 create-security-group \
  --group-name "NetworkLab-SG-Endpoints" \
  --description "SG pour Interface VPC Endpoints" \
  --vpc-id $VPC_A --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_EP \
  --protocol tcp --port 443 --cidr 10.1.0.0/16
echo "SG Endpoints : $SG_EP"

echo "=== [3/4] VPC Endpoints SSM (Interface - accès EC2 sans bastion) ==="
for SERVICE in ssm ssmmessages ec2messages; do
  EP_ID=$(aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_A \
    --service-name com.amazonaws.${REGION}.${SERVICE} \
    --vpc-endpoint-type Interface \
    --subnet-ids $SUB_A_PRIV \
    --security-group-ids $SG_EP \
    --private-dns-enabled \
    --query 'VpcEndpoint.VpcEndpointId' --output text)
  aws ec2 create-tags --resources $EP_ID --tags Key=Name,Value="NetworkLab-EP-${SERVICE}"
  echo "  $SERVICE Endpoint : $EP_ID"
done

echo "=== [4/4] VPC Endpoint Secrets Manager ==="
EP_SM=$(aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_A \
  --service-name com.amazonaws.${REGION}.secretsmanager \
  --vpc-endpoint-type Interface \
  --subnet-ids $SUB_A_PRIV \
  --security-group-ids $SG_EP \
  --private-dns-enabled \
  --query 'VpcEndpoint.VpcEndpointId' --output text)
aws ec2 create-tags --resources $EP_SM --tags Key=Name,Value="NetworkLab-EP-SecretsManager"
echo "Secrets Manager Endpoint : $EP_SM"

echo ""
echo "=== VPC ENDPOINTS TERMINÉS ==="
echo "Les instances EC2 dans le subnet privé peuvent maintenant :"
echo "  - Accéder à S3 sans NAT Gateway (économie de coût)"
echo "  - Être gérées via SSM Session Manager sans bastion SSH"
echo "  - Récupérer les secrets Secrets Manager sans Internet"
