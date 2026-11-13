#!/bin/bash
# =============================================================
# AWS Cost Optimization - Spot Instances (jusqu'à 90% moins cher)
# Crée un ASG mixte On-Demand + Spot pour workloads non-critiques
# =============================================================
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="$REGION"
: "${AMI_ID:?Export AMI_ID (existing compatible EC2 AMI)}"
: "${SUBNET_IDS:?Export SUBNET_IDS as comma-separated existing subnets}"
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
aws ec2 describe-images --image-ids "$AMI_ID" >/dev/null
aws ec2 describe-subnets --subnet-ids "${SUBNET_ARRAY[@]}" >/dev/null
echo "Account: $(aws sts get-caller-identity --query Account --output text)"
echo "Region=$REGION AMI=$AMI_ID Subnets=$SUBNET_IDS"
read -r -p "Spot and On-Demand instances are billable. Type CREATE: " CONSENT
[[ "$CONSENT" == "CREATE" ]] || { echo "Cancelled"; exit 1; }
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

echo "=== [3/3] Pricing warning ==="
echo "Spot pricing and interruption rates change continuously."
echo "Inspect current AWS EC2 Spot prices and Cost Explorer before relying on savings."
echo "Resources have been requested; verify instances and clean them up after the lab."
