# Lab 01 — Secure AWS Web Application Architecture

**Goal:** build and inspect a segmented AWS application infrastructure with public ingress, private compute and a private database, with optional HTTPS and WAF protection.

> **Lab only:** the scripts create **billable resources** and have not been live-deployed as part of this documentation update. Perform them in a dedicated AWS sandbox and check the current AWS CLI service requirements. They are not production Infrastructure as Code.

## Target topology

```text
Internet -> public ALB -> private EC2 Auto Scaling Group -> private RDS MySQL
                |                  |
         ACM HTTPS optional     NAT egress
                |
             AWS WAF
```

**AWS services:** VPC, public/private subnets in two AZs, route tables, Security Groups, IGW, NAT Gateway, ALB, EC2 Auto Scaling, RDS, WAF and optional VPC Flow Logs.

## Files and roles

| Script | Creates or configures |
| --- | --- |
| `scripts/setup_vpc.sh` | VPC, two AZs, subnets, routes, Internet/NAT gateways, security groups |
| `scripts/deploy_ec2.sh` | Existing-AMI EC2 launch template, target group, ALB, listeners and Auto Scaling |
| `scripts/setup_rds.sh` | MySQL RDS with AWS-managed master password and private network settings |
| `scripts/setup_waf.sh` | Managed-rule WAF ACL, association with ALB and optional S3 log delivery |

## Preflight

```bash
aws sts get-caller-identity
export AWS_REGION=us-east-1  # set your actual lab region
export AWS_DEFAULT_REGION="$AWS_REGION"
aws ec2 describe-availability-zones --query "AvailabilityZones[*].ZoneName" --output table
aws rds describe-db-engine-versions --engine mysql \
  --query "DBEngineVersions[*].[EngineVersion,DBParameterGroupFamily]" --output table
```

**Do not run blindly:** NAT, WAF, ALB, EC2, RDS, Secrets Manager and log storage may incur charges. You must prepare a teardown plan.

## Order of operations

### 1. Create the VPC

```bash
bash scripts/setup_vpc.sh
```

By default this creates an isolated lab VPC using the selected region's first two available AZs. It saves non-secret resource IDs in `/tmp/vpc_ids.env`. **To enable VPC Flow Logs**, set `FLOW_LOGS_ROLE_ARN` to a legitimate IAM role allowing delivery to CloudWatch Logs; otherwise this optional step is skipped and not falsely reported as active.

### 2. Deploy compute and load balancer

The EC2 bootstrap installs software using `yum`, so choose an **available compatible Amazon Linux 2 AMI**. Validate AMI and key-pair IDs for your region.

```bash
export AMI_ID=ami-REPLACE-WITH-VALID-LAB-IMAGE
export KEY_NAME=REPLACE-WITH-YOUR-KEY-PAIR

# Optional: if you have a matching ISSUED ACM certificate in this region,
# export CERT_ARN=arn:aws:acm:...
bash scripts/deploy_ec2.sh
```

When `CERT_ARN` is set, the script creates an HTTPS listener and redirects HTTP to HTTPS. Without a certificate it uses **HTTP-only mode for testing**, rather than redirecting to a nonexistent HTTPS listener. **HTTP-only is not suitable for production or sensitive data.**

An AWS default ALB DNS hostname may not match your certificate: configure a suitable domain and Route53 alias to validate HTTPS in a browser.

### 3. Set up RDS (optional, billable)

```bash
export MYSQL_ENGINE_VERSION=REPLACE-WITH-SUPPORTED-MYSQL-8_0-VERSION
export DB_CLASS=db.t3.micro
export MULTI_AZ=false           # true costs more
bash scripts/setup_rds.sh
```

The script requires interactive cost confirmation, enforces private RDS networking, enables encryption/deletion protection, requests TLS transport and uses **RDS-managed Secrets Manager credentials** instead of printing a generated password. Verify RDS status and secret rotation independently.

### 4. Apply WAF (optional, billable)

```bash
bash scripts/setup_waf.sh
```

The script finds the existing ALB ARN instead of using placeholder account IDs and uses an AWS WAF-compatible S3 logging bucket name. Its success still depends on correct AWS WAF/S3 permissions; review cost and production policies first.

## Validation

```bash
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,State]' --output table
aws elbv2 describe-load-balancers --names SecureWebApp-ALB
aws elbv2 describe-target-health --target-group-arn YOUR_TARGET_GROUP_ARN
aws rds describe-db-instances --db-instance-identifier SecureWebApp-RDS
```

The final command applies only if RDS was deployed. Check networking, target health, TLS, ALB/WAF metrics and database encryption before treating the environment as valid.

## Limitations and next steps

- Bash scripts are stateful and not idempotent; interrupted steps may leave billable resources.
- No automatic teardown is provided.
- The application is a demo bootstrap, not a reviewed production workload.
- Security groups and IAM should be reviewed for the chosen use case.
- Automate the lifecycle using Terraform / CloudFormation and policy checks in a future iteration.

**Skills:** AWS network security, IAM awareness, ALB/ASG, RDS, ACM, WAF, segmentation, operational verification.
