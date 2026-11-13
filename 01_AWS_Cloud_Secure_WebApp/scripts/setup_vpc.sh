#!/bin/bash
# =============================================================
# AWS Secure WebApp - VPC Setup
# Crée : VPC, Subnets (public/private), IGW, NAT, Route Tables
# =============================================================
set -euo pipefail
umask 077

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="$REGION"
VPC_CIDR="10.0.0.0/16"
PUB_SUB1_CIDR="10.0.1.0/24"
PUB_SUB2_CIDR="10.0.2.0/24"
PRIV_SUB1_CIDR="10.0.10.0/24"
PRIV_SUB2_CIDR="10.0.20.0/24"
# Choose available AZs dynamically; hardcoded region suffixes are not universal.
AZ1="$(aws ec2 describe-availability-zones --region "$REGION" \
  --query 'AvailabilityZones[0].ZoneName' --output text)"
AZ2="$(aws ec2 describe-availability-zones --region "$REGION" \
  --query 'AvailabilityZones[1].ZoneName' --output text)"
[[ "$AZ1" != "None" && "$AZ2" != "None" && "$AZ1" != "$AZ2" ]] || {
  echo "Two availability zones are required." >&2; exit 1;
}
PROJECT="SecureWebApp"

echo "=== [1/8] Création du VPC ==="
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --region $REGION \
  --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="${PROJECT}-VPC"
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
echo "VPC créé : $VPC_ID"

echo "=== [2/8] Création des Subnets ==="
PUB1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUB_SUB1_CIDR \
  --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB1 --tags Key=Name,Value="${PROJECT}-Public-1a"
aws ec2 modify-subnet-attribute --subnet-id $PUB1 --map-public-ip-on-launch

PUB2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUB_SUB2_CIDR \
  --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUB2 --tags Key=Name,Value="${PROJECT}-Public-1b"
aws ec2 modify-subnet-attribute --subnet-id $PUB2 --map-public-ip-on-launch

PRIV1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIV_SUB1_CIDR \
  --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PRIV1 --tags Key=Name,Value="${PROJECT}-Private-1a"

PRIV2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIV_SUB2_CIDR \
  --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PRIV2 --tags Key=Name,Value="${PROJECT}-Private-1b"
echo "Subnets créés : pub($PUB1,$PUB2) priv($PRIV1,$PRIV2)"

echo "=== [3/8] Internet Gateway ==="
IGW=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
aws ec2 create-tags --resources $IGW --tags Key=Name,Value="${PROJECT}-IGW"
echo "IGW : $IGW"

echo "=== [4/8] Elastic IP + NAT Gateway ==="
EIP=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT=$(aws ec2 create-nat-gateway --subnet-id $PUB1 --allocation-id $EIP \
  --query 'NatGateway.NatGatewayId' --output text)
aws ec2 create-tags --resources $NAT --tags Key=Name,Value="${PROJECT}-NAT"
echo "Attente NAT Gateway (60s)..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT
echo "NAT Gateway : $NAT"

echo "=== [5/8] Route Tables ==="
# Table publique
PUB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $PUB_RT --tags Key=Name,Value="${PROJECT}-Public-RT"
aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB1
aws ec2 associate-route-table --route-table-id $PUB_RT --subnet-id $PUB2

# Table privée
PRIV_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $PRIV_RT --tags Key=Name,Value="${PROJECT}-Private-RT"
aws ec2 create-route --route-table-id $PRIV_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV1
aws ec2 associate-route-table --route-table-id $PRIV_RT --subnet-id $PRIV2
echo "Route Tables configurées"

echo "=== [6/8] VPC Flow Logs ==="
# A CloudWatch Logs IAM delivery role is required; do not invent an ARN.
if [[ -n "${FLOW_LOGS_ROLE_ARN:-}" ]]; then
  LOG_GROUP="/aws/vpc/flowlogs/${PROJECT}"
  aws logs create-log-group --log-group-name "$LOG_GROUP" 2>/dev/null || true
  aws ec2 create-flow-logs \
    --resource-type VPC --resource-ids "$VPC_ID" --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name "$LOG_GROUP" \
    --deliver-logs-permission-arn "$FLOW_LOGS_ROLE_ARN"
  echo "Flow Logs request submitted to CloudWatch Logs."
else
  echo "Flow Logs SKIPPED: export FLOW_LOGS_ROLE_ARN (with correct IAM permissions)."
fi

echo "=== [7/8] Security Groups ==="
# SG ALB - accès public 80/443
SG_ALB=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-SG-ALB" \
  --description "ALB Security Group" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_ALB --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ALB --protocol tcp --port 80  --cidr 0.0.0.0/0

# SG EC2 - seulement depuis ALB
SG_EC2=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-SG-EC2" \
  --description "EC2 Security Group" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_EC2 --protocol tcp --port 80 \
  --source-group $SG_ALB

# SG RDS - seulement depuis EC2
SG_RDS=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-SG-RDS" \
  --description "RDS Security Group" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_RDS --protocol tcp --port 3306 \
  --source-group $SG_EC2

echo "=== [8/8] Export IDs ==="
cat > /tmp/vpc_ids.env << EOF
export VPC_ID=$VPC_ID
export PUB_SUBNET1=$PUB1
export PUB_SUBNET2=$PUB2
export PRIV_SUBNET1=$PRIV1
export PRIV_SUBNET2=$PRIV2
export IGW_ID=$IGW
export NAT_ID=$NAT
export SG_ALB=$SG_ALB
export SG_EC2=$SG_EC2
export SG_RDS=$SG_RDS
EOF
echo "Variables exportées dans /tmp/vpc_ids.env"
echo ""
echo "=== VPC SETUP TERMINÉ ==="
