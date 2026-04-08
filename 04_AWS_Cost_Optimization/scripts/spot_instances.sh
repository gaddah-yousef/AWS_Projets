#!/bin/bash
# =============================================================
# AWS Cost Optimization - Spot Instances (jusqu'à 90% moins cher)
# Crée un ASG mixte On-Demand + Spot pour workloads non-critiques
# =============================================================
set -euo pipefail

REGION="us-east-1"
AMI_ID="ami-0c02fb55956c7d316"  # Amazon Linux 2
SUBNET_IDS="${SUBNET_IDS:-subnet-XXXX,subnet-YYYY}"
PROJECT="CostOpt"

echo "=== [1/3] Launch Template avec Spot ==="
LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "${PROJECT}-Spot-LT" \
  --launch-template-data '{
    "ImageId": "'$AMI_ID'",
    "InstanceType": "t3.micro",
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/xvda",
      "Ebs": {"VolumeSize": 20, "VolumeType": "gp3", "DeleteOnTermination": true}
    }],
    "Monitoring": {"Enabled": true},
    "UserData": "'$(echo '#!/bin/bash
yum install -y stress
echo "Spot instance ready" > /tmp/ready' | base64 -w 0)'"
  }' \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
echo "Launch Template Spot : $LT_ID"

echo "=== [2/3] Auto Scaling Group Mixte (25% On-Demand + 75% Spot) ==="
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${PROJECT}-Mixed-ASG" \
  --min-size 1 --max-size 6 --desired-capacity 4 \
  --vpc-zone-identifier "$SUBNET_IDS" \
  --mixed-instances-policy '{
    "LaunchTemplate": {
      "LaunchTemplateSpecification": {
        "LaunchTemplateId": "'$LT_ID'",
        "Version": "$Latest"
      },
      "Overrides": [
        {"InstanceType": "t3.micro"},
        {"InstanceType": "t3a.micro"},
        {"InstanceType": "t2.micro"}
      ]
    },
    "InstancesDistribution": {
      "OnDemandBaseCapacity": 1,
      "OnDemandPercentageAboveBaseCapacity": 25,
      "SpotAllocationStrategy": "capacity-optimized",
      "SpotInstancePools": 3
    }
  }' \
  --tags Key=Name,Value="${PROJECT}-Mixed",Key=SpotEnabled,Value=true

echo "Auto Scaling Group mixte créé"

echo "=== [3/3] Estimation des économies ==="
ON_DEMAND_PRICE=0.0116  # t3.micro us-east-1 $/heure
SPOT_PRICE=0.0014       # t3.micro Spot typique
INSTANCES=4
HOURS_MONTH=730

ON_DEMAND_TOTAL=$(echo "$INSTANCES * $ON_DEMAND_PRICE * $HOURS_MONTH" | bc)
# Mix: 1 OD + 3 Spot
MIXED_TOTAL=$(echo "(1 * $ON_DEMAND_PRICE + 3 * $SPOT_PRICE) * $HOURS_MONTH" | bc)

echo ""
echo "=== SPOT INSTANCES CONFIGURÉES ==="
echo "Configuration: 1 On-Demand + 3 Spot (capacity-optimized)"
echo "Stratégie allocation: capacity-optimized (moins d'interruptions)"
echo ""
echo "Estimation économies mensuelles:"
echo "  On-Demand uniquement : ~\$$ON_DEMAND_TOTAL/mois"
echo "  Mix OD+Spot          : ~\$$MIXED_TOTAL/mois"
echo ""
echo "Types Spot acceptés: t3.micro, t3a.micro, t2.micro (diversification)"
