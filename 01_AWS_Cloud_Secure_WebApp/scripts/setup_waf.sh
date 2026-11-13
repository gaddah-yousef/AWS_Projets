#!/bin/bash
# =============================================================
# AWS Secure WebApp - WAF v2 avec règles OWASP Top 10
# =============================================================
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_DEFAULT_REGION="$REGION"
PROJECT="${PROJECT:-SecureWebApp}"
# Resolve the real ALB ARN; never use placeholder account IDs.
ALB_ARN="${ALB_ARN:-$(aws elbv2 describe-load-balancers \
  --names "${PROJECT}-ALB" --query 'LoadBalancers[0].LoadBalancerArn' --output text)}"
[[ "$ALB_ARN" == arn:aws:elasticloadbalancing:* ]] || {
  echo "Valid ALB_ARN required" >&2; exit 1;
}
echo "Account: $(aws sts get-caller-identity --query Account --output text)"
echo "Region: $REGION, ALB: $ALB_ARN"
read -r -p "Creates billable AWS WAF resources. Type CREATE: " CONFIRM
[[ "$CONFIRM" == "CREATE" ]] || { echo "Cancelled."; exit 1; }

echo "=== [1/3] Création Web ACL WAF ==="
WAF_ARN=$(aws wafv2 create-web-acl \
  --name "${PROJECT}-WAF" \
  --scope REGIONAL \
  --region $REGION \
  --default-action Allow={} \
  --rules '[
    {
      "Name": "AWSManagedRulesCommonRuleSet",
      "Priority": 1,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "CommonRuleSet"
      }
    },
    {
      "Name": "AWSManagedRulesSQLiRuleSet",
      "Priority": 2,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesSQLiRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "SQLiRuleSet"
      }
    },
    {
      "Name": "RateLimit",
      "Priority": 3,
      "Action": {"Block": {}},
      "Statement": {
        "RateBasedStatement": {
          "Limit": 2000,
          "AggregateKeyType": "IP"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "RateLimit"
      }
    }
  ]' \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName="${PROJECT}WAF" \
  --query 'Summary.ARN' --output text)
echo "WAF ACL créé : $WAF_ARN"

echo "=== [2/3] Association WAF avec ALB ==="
aws wafv2 associate-web-acl \
  --web-acl-arn $WAF_ARN \
  --resource-arn $ALB_ARN \
  --region $REGION
echo "WAF associé à l'ALB"

echo "=== [3/3] Activation des logs WAF vers S3 ==="
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="aws-waf-logs-${PROJECT,,}-${ACCOUNT}-${REGION}"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
fi
aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-versioning --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
aws wafv2 put-logging-configuration \
  --logging-configuration "ResourceArn=$WAF_ARN,LogDestinationConfigs=[arn:aws:s3:::${BUCKET_NAME}]" \
  --region "$REGION" || echo "WAF logging not enabled: review WAF/S3 IAM permissions."

echo ""
echo "=== WAF SETUP TERMINÉ ==="
echo "Règles actives: OWASP Common + SQLi + Rate Limit (2000 req/5min/IP)"
