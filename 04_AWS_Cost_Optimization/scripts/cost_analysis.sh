#!/usr/bin/env bash
# Read-only AWS Cost Explorer analysis; may require the Cost Explorer service to be enabled.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
START="$(date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-30d +%Y-%m-%d)"
END="$(date -u +%Y-%m-%d)"
echo "AWS account:"
aws sts get-caller-identity --query Account --output text
echo "Cost Explorer — $START to $END (end exclusive, currency provided by AWS):"
aws ce get-cost-and-usage --time-period "Start=$START,End=$END"   --granularity MONTHLY --metrics UnblendedCost   --group-by Type=DIMENSION,Key=SERVICE   --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.UnblendedCost.Amount,Metrics.UnblendedCost.Unit]'   --output table
echo "Read-only analysis complete. Costs are AWS estimates, not a bill."
