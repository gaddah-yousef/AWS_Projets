#!/bin/bash
# =============================================================
# AWS Secure WebApp - EC2 + Auto Scaling + ALB Deployment
# =============================================================
set -euo pipefail

source /tmp/vpc_ids.env

REGION="us-east-1"
AMI_ID="ami-0c02fb55956c7d316"   # Amazon Linux 2 us-east-1
INSTANCE_TYPE="t3.micro"
KEY_NAME="my-keypair"            # Modifier avec votre clé
PROJECT="SecureWebApp"
MIN_SIZE=2
MAX_SIZE=4
DESIRED=2

echo "=== [1/5] Launch Template (User Data - Nginx + app) ==="
USER_DATA=$(cat << 'USERDATA' | base64 -w 0
#!/bin/bash
yum update -y
yum install -y nginx python3 python3-pip
pip3 install flask gunicorn boto3

# Application Flask simple
mkdir -p /app
cat > /app/app.py << 'PYEOF'
from flask import Flask, jsonify
import socket, os
app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        "status": "ok",
        "host": socket.gethostname(),
        "env": os.environ.get("APP_ENV", "production")
    })

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200
PYEOF

# Démarrage Gunicorn
cat > /etc/systemd/system/webapp.service << 'SVCEOF'
[Unit]
Description=Flask WebApp
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/app
ExecStart=/usr/local/bin/gunicorn --workers 2 --bind 0.0.0.0:8000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
SVCEOF

# Nginx reverse proxy
cat > /etc/nginx/conf.d/webapp.conf << 'NGINXEOF'
server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location /health {
        proxy_pass http://127.0.0.1:8000/health;
    }
}
NGINXEOF

systemctl enable nginx webapp
systemctl start nginx webapp
USERDATA
)

LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "${PROJECT}-LT" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"$INSTANCE_TYPE\",
    \"KeyName\": \"$KEY_NAME\",
    \"SecurityGroupIds\": [\"$SG_EC2\"],
    \"UserData\": \"$USER_DATA\",
    \"BlockDeviceMappings\": [{
      \"DeviceName\": \"/dev/xvda\",
      \"Ebs\": {\"VolumeSize\": 20, \"VolumeType\": \"gp3\", \"Encrypted\": true}
    }],
    \"Monitoring\": {\"Enabled\": true},
    \"MetadataOptions\": {\"HttpTokens\": \"required\"}
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
echo "Launch Template : $LT_ID"

echo "=== [2/5] Application Load Balancer ==="
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${PROJECT}-ALB" \
  --subnets $PUB_SUBNET1 $PUB_SUBNET2 \
  --security-groups $SG_ALB \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "ALB ARN : $ALB_ARN"

echo "=== [3/5] Target Group ==="
TG_ARN=$(aws elbv2 create-target-group \
  --name "${PROJECT}-TG" \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --health-check-protocol HTTP \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --matcher HttpCode=200 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "Target Group : $TG_ARN"

# Listener HTTP → redirect HTTPS
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}'

# Listener HTTPS (nécessite certificat ACM)
# CERT_ARN="arn:aws:acm:us-east-1:ACCOUNT:certificate/xxxx"
# aws elbv2 create-listener \
#   --load-balancer-arn $ALB_ARN \
#   --protocol HTTPS --port 443 \
#   --certificates CertificateArn=$CERT_ARN \
#   --default-actions Type=forward,TargetGroupArn=$TG_ARN

echo "=== [4/5] Auto Scaling Group ==="
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${PROJECT}-ASG" \
  --launch-template LaunchTemplateId=$LT_ID,Version='$Latest' \
  --min-size $MIN_SIZE --max-size $MAX_SIZE --desired-capacity $DESIRED \
  --vpc-zone-identifier "$PRIV_SUBNET1,$PRIV_SUBNET2" \
  --target-group-arns $TG_ARN \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --tags Key=Name,Value="${PROJECT}-EC2",PropagateAtLaunch=true

# Scaling policy - CPU > 70%
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "${PROJECT}-ASG" \
  --policy-name "ScaleOut-CPU70" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"},
    "TargetValue": 70.0
  }'
echo "Auto Scaling Group créé"

echo "=== [5/5] Récupération DNS ALB ==="
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)
echo ""
echo "=== DÉPLOIEMENT EC2/ALB TERMINÉ ==="
echo "URL Application : http://$ALB_DNS"
echo "(HTTPS disponible après ajout du certificat ACM)"
