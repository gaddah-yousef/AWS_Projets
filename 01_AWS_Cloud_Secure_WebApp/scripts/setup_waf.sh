#!/bin/bash
# =============================================================
# AWS Secure WebApp - WAF v2 avec règles OWASP Top 10
# =============================================================
set -euo pipefail

REGION="us-east-1"
PROJECT="SecureWebApp"
# Remplacer par l'ARN de votre ALB
ALB_ARN="${ALB_ARN:-arn:aws:elasticloadbalancing:us-east-1:ACCOUNT_ID:loadbalancer/app/${PROJECT}-ALB/xxxx}"

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
BUCKET_NAME="waf-logs-${PROJECT,,}-${ACCOUNT}"
aws s3 mb s3://${BUCKET_NAME} --region $REGION 2>/dev/null || true
aws s3api put-bucket-versioning --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
aws wafv2 put-logging-configuration \
  --logging-configuration "ResourceArn=$WAF_ARN,LogDestinationConfigs=[arn:aws:s3:::${BUCKET_NAME}]" \
  --region $REGION 2>/dev/null || echo "Logging WAF: droits S3 IAM requis"

echo ""
echo "=== WAF SETUP TERMINÉ ==="
echo "Règles actives: OWASP Common + SQLi + Rate Limit (2000 req/5min/IP)"
