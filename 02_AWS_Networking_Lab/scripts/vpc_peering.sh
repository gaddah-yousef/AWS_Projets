#!/bin/bash
# =============================================================
# AWS Networking Lab - VPC Peering complet
# Crée 2 VPCs et établit un peering avec routes configurées
# =============================================================
set -euo pipefail

REGION="us-east-1"
VPC_A_CIDR="10.1.0.0/16"
VPC_B_CIDR="10.2.0.0/16"
SUB_A_PUB="10.1.1.0/24"
SUB_A_PRIV="10.1.10.0/24"
SUB_B_PRIV="10.2.10.0/24"

echo "=== [1/6] Création VPC-A ==="
VPC_A=$(aws ec2 create-vpc --cidr-block $VPC_A_CIDR --region $REGION \
  --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_A --tags Key=Name,Value="NetworkLab-VPC-A"
aws ec2 modify-vpc-attribute --vpc-id $VPC_A --enable-dns-hostnames

SUB_A_PUB_ID=$(aws ec2 create-subnet --vpc-id $VPC_A --cidr-block $SUB_A_PUB \
  --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUB_A_PUB_ID --tags Key=Name,Value="VPC-A-Public"
aws ec2 modify-subnet-attribute --subnet-id $SUB_A_PUB_ID --map-public-ip-on-launch

SUB_A_PRIV_ID=$(aws ec2 create-subnet --vpc-id $VPC_A --cidr-block $SUB_A_PRIV \
  --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUB_A_PRIV_ID --tags Key=Name,Value="VPC-A-Private"
echo "VPC-A : $VPC_A"

echo "=== [2/6] Création VPC-B ==="
VPC_B=$(aws ec2 create-vpc --cidr-block $VPC_B_CIDR --region $REGION \
  --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_B --tags Key=Name,Value="NetworkLab-VPC-B"
aws ec2 modify-vpc-attribute --vpc-id $VPC_B --enable-dns-hostnames

SUB_B_PRIV_ID=$(aws ec2 create-subnet --vpc-id $VPC_B --cidr-block $SUB_B_PRIV \
  --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUB_B_PRIV_ID --tags Key=Name,Value="VPC-B-Private"
echo "VPC-B : $VPC_B"

echo "=== [3/6] IGW pour VPC-A ==="
IGW=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_A
RT_A_PUB=$(aws ec2 create-route-table --vpc-id $VPC_A --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RT_A_PUB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
aws ec2 associate-route-table --route-table-id $RT_A_PUB --subnet-id $SUB_A_PUB_ID

echo "=== [4/6] VPC Peering ==="
PEERING_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_A \
  --peer-vpc-id $VPC_B \
  --peer-region $REGION \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)
aws ec2 create-tags --resources $PEERING_ID --tags Key=Name,Value="NetworkLab-Peering-A-B"

# Accepter le peering
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PEERING_ID
echo "Peering créé et accepté : $PEERING_ID"

echo "=== [5/6] Routes inter-VPC ==="
# Route table VPC-A (private) → VPC-B via peering
RT_A_PRIV=$(aws ec2 create-route-table --vpc-id $VPC_A --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $RT_A_PRIV --tags Key=Name,Value="VPC-A-Private-RT"
aws ec2 create-route --route-table-id $RT_A_PRIV \
  --destination-cidr-block $VPC_B_CIDR \
  --vpc-peering-connection-id $PEERING_ID
aws ec2 associate-route-table --route-table-id $RT_A_PRIV --subnet-id $SUB_A_PRIV_ID

# Route table VPC-B → VPC-A via peering
RT_B=$(aws ec2 create-route-table --vpc-id $VPC_B --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $RT_B --tags Key=Name,Value="VPC-B-Private-RT"
aws ec2 create-route --route-table-id $RT_B \
  --destination-cidr-block $VPC_A_CIDR \
  --vpc-peering-connection-id $PEERING_ID
aws ec2 associate-route-table --route-table-id $RT_B --subnet-id $SUB_B_PRIV_ID
echo "Routes configurées dans les deux sens"

echo "=== [6/6] Security Groups pour tests ping ==="
SG_A=$(aws ec2 create-security-group --group-name "NetworkLab-SG-A" \
  --description "VPC-A test SG" --vpc-id $VPC_A --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_A \
  --protocol icmp --port -1 --cidr $VPC_B_CIDR
aws ec2 authorize-security-group-ingress --group-id $SG_A \
  --protocol tcp --port 22 --cidr $VPC_B_CIDR

SG_B=$(aws ec2 create-security-group --group-name "NetworkLab-SG-B" \
  --description "VPC-B test SG" --vpc-id $VPC_B --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_B \
  --protocol icmp --port -1 --cidr $VPC_A_CIDR
aws ec2 authorize-security-group-ingress --group-id $SG_B \
  --protocol tcp --port 22 --cidr $VPC_A_CIDR

# Export
cat > /tmp/networking_ids.env << EOF
export VPC_A=$VPC_A
export VPC_B=$VPC_B
export SUB_A_PUB=$SUB_A_PUB_ID
export SUB_A_PRIV=$SUB_A_PRIV_ID
export SUB_B_PRIV=$SUB_B_PRIV_ID
export PEERING_ID=$PEERING_ID
export SG_A=$SG_A
export SG_B=$SG_B
export RT_A_PRIV=$RT_A_PRIV
EOF

echo ""
echo "=== VPC PEERING TERMINÉ ==="
echo "VPC-A: $VPC_A ($VPC_A_CIDR) ↔ VPC-B: $VPC_B ($VPC_B_CIDR)"
echo "Peering: $PEERING_ID"
