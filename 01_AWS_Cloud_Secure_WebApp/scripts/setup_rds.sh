#!/usr/bin/env bash
# Creates a protected MySQL RDS lab instance using AWS-managed master secrets.
# Provisioning RDS costs money; review class, storage and backup charges first.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ENV_FILE="${VPC_ENV_FILE:-/tmp/vpc_ids.env}"
[[ -r "$ENV_FILE" ]] || { echo "Missing $ENV_FILE: run setup_vpc.sh." >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

PROJECT="${PROJECT:-SecureWebApp}"
DB_NAME="${DB_NAME:-webappdb}"
DB_USER="${DB_USER:-admin}"
DB_CLASS="${DB_CLASS:-db.t3.micro}"
: "${MYSQL_ENGINE_VERSION:?Set MYSQL_ENGINE_VERSION to a MySQL 8.0 engine version available in your region}"
PARAM_GROUP="${PROJECT}-mysql-params"
SUBNET_GROUP="${PROJECT}-rds-subnets"
MULTI_AZ="${MULTI_AZ:-false}"
[[ "$MULTI_AZ" == "true" || "$MULTI_AZ" == "false" ]] || {
  echo "MULTI_AZ must be true or false" >&2; exit 1;
}
aws sts get-caller-identity >/dev/null
echo "RDS region=$AWS_DEFAULT_REGION class=$DB_CLASS version=$MYSQL_ENGINE_VERSION multiAZ=$MULTI_AZ"
read -r -p "This creates billable AWS resources. Type CREATE: " CONFIRM
[[ "$CONFIRM" == "CREATE" ]] || { echo "Cancelled."; exit 1; }

if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP"   >/dev/null 2>&1; then
  aws rds create-db-subnet-group     --db-subnet-group-name "$SUBNET_GROUP"     --db-subnet-group-description "Private subnet group for $PROJECT"     --subnet-ids "$PRIV_SUBNET1" "$PRIV_SUBNET2"
fi
if ! aws rds describe-db-parameter-groups --db-parameter-group-name "$PARAM_GROUP"   >/dev/null 2>&1; then
  aws rds create-db-parameter-group     --db-parameter-group-name "$PARAM_GROUP"     --db-parameter-group-family mysql8.0     --description "Require TLS on MySQL connections"
fi
aws rds modify-db-parameter-group   --db-parameter-group-name "$PARAM_GROUP"   --parameters "ParameterName=require_secure_transport,ParameterValue=ON,ApplyMethod=immediate"

AVAILABILITY=(--no-multi-az)
if [[ "$MULTI_AZ" == "true" ]]; then AVAILABILITY=(--multi-az); fi

aws rds create-db-instance   --db-instance-identifier "${PROJECT}-RDS"   --db-instance-class "$DB_CLASS"   --engine mysql --engine-version "$MYSQL_ENGINE_VERSION"   --master-username "$DB_USER" --manage-master-user-password   --db-name "$DB_NAME"   --db-subnet-group-name "$SUBNET_GROUP"   --vpc-security-group-ids "$SG_RDS"   --db-parameter-group-name "$PARAM_GROUP"   --backup-retention-period 7   "${AVAILABILITY[@]}"   --storage-type gp3 --allocated-storage 20 --storage-encrypted   --deletion-protection --no-publicly-accessible --auto-minor-version-upgrade   --tags Key=Name,Value="${PROJECT}-RDS" Key=Project,Value="$PROJECT"

echo "RDS creation requested; credentials managed by RDS in Secrets Manager."
echo "Check the instance status and associated MasterUserSecret ARN using:"
echo "aws rds describe-db-instances --db-instance-identifier ${PROJECT}-RDS"
echo "Note: master secret rotation must be configured/verified separately."
