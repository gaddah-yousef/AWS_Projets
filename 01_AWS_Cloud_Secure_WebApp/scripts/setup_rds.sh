#!/bin/bash
# =============================================================
# AWS Secure WebApp - RDS MySQL Multi-AZ + Secrets Manager
# =============================================================
set -euo pipefail

source /tmp/vpc_ids.env

REGION="us-east-1"
PROJECT="SecureWebApp"
DB_NAME="webappdb"
DB_USER="admin"
DB_PASS=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 20)
DB_CLASS="db.t3.micro"

echo "=== [1/4] Subnet Group RDS ==="
aws rds create-db-subnet-group \
  --db-subnet-group-name "${PROJECT}-RDS-SubnetGroup" \
  --db-subnet-group-description "RDS Subnet Group pour ${PROJECT}" \
  --subnet-ids $PRIV_SUBNET1 $PRIV_SUBNET2
echo "Subnet Group créé"

echo "=== [2/4] Parametre Group (sécurité MySQL) ==="
aws rds create-db-parameter-group \
  --db-parameter-group-name "${PROJECT}-mysql-params" \
  --db-parameter-group-family mysql8.0 \
  --description "Secure MySQL params"

# Forcer SSL
aws rds modify-db-parameter-group \
  --db-parameter-group-name "${PROJECT}-mysql-params" \
  --parameters "ParameterName=require_secure_transport,ParameterValue=ON,ApplyMethod=immediate"
echo "Parameter Group configuré (SSL forcé)"

echo "=== [3/4] Création RDS MySQL Multi-AZ ==="
aws rds create-db-instance \
  --db-instance-identifier "${PROJECT}-RDS" \
  --db-instance-class $DB_CLASS \
  --engine mysql \
  --engine-version 8.0 \
  --master-username $DB_USER \
  --master-user-password "$DB_PASS" \
  --db-name $DB_NAME \
  --db-subnet-group-name "${PROJECT}-RDS-SubnetGroup" \
  --vpc-security-group-ids $SG_RDS \
  --db-parameter-group-name "${PROJECT}-mysql-params" \
  --backup-retention-period 7 \
  --multi-az \
  --storage-type gp3 \
  --allocated-storage 20 \
  --storage-encrypted \
  --deletion-protection \
  --no-publicly-accessible \
  --auto-minor-version-upgrade \
  --tags Key=Name,Value="${PROJECT}-RDS" Key=Project,Value=$PROJECT
echo "RDS en cours de création (5-10 min)..."

echo "=== [4/4] Stockage mot de passe dans Secrets Manager ==="
aws secretsmanager create-secret \
  --name "${PROJECT}/rds/credentials" \
  --description "RDS credentials pour ${PROJECT}" \
  --secret-string "{\"username\":\"$DB_USER\",\"password\":\"$DB_PASS\",\"dbname\":\"$DB_NAME\"}"

echo ""
echo "=== RDS SETUP TERMINÉ ==="
echo "Credentials stockés dans Secrets Manager : ${PROJECT}/rds/credentials"
echo "Ne pas stocker le mot de passe en clair dans vos scripts !"
