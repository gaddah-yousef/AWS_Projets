#!/bin/bash
# =============================================================
# AWS Cost Optimization - Nettoyage des ressources inutilisées
# Inclut: EIPs, Snapshots anciens, Volumes détachés, AMIs vieilles
# SAFE: dry-run par défaut. Passer --execute pour vraiment supprimer.
# =============================================================
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
EXECUTE=false
SNAPSHOT_AGE_DAYS=30
DRY_RUN_MSG="[DRY-RUN]"

if [[ "${1:-}" == "--execute" ]]; then
  EXECUTE=true
  DRY_RUN_MSG="[EXECUTE]"
  echo "⚠️  MODE EXECUTE - Les ressources seront SUPPRIMÉES"
  read -p "Confirmer ? (yes/no): " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && echo "Annulé." && exit 0
else
  echo "ℹ️  MODE DRY-RUN - Aucune suppression. Passer --execute pour confirmer."
fi

echo ""
echo "=== [$DRY_RUN_MSG 1/5] Elastic IPs non associées ==="
UNASSOC_EIPS=$(aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].[AllocationId,PublicIp]' \
  --output text --region $REGION)

if [[ -z "$UNASSOC_EIPS" ]]; then
  echo "Aucune EIP non associée trouvée."
else
  echo "EIPs non associées (coût: ~3.60$/mois chacune):"
  echo "$UNASSOC_EIPS" | while read ALLOC_ID PUBLIC_IP; do
    echo "  - $PUBLIC_IP ($ALLOC_ID)"
    if $EXECUTE; then
      aws ec2 release-address --allocation-id $ALLOC_ID --region $REGION
      echo "    → Libérée"
    fi
  done
fi

echo ""
echo "=== [$DRY_RUN_MSG 2/5] Volumes EBS détachés ==="
DETACHED_VOLS=$(aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query 'Volumes[*].[VolumeId,Size,VolumeType,CreateTime]' \
  --output text --region $REGION)

if [[ -z "$DETACHED_VOLS" ]]; then
  echo "Aucun volume détaché trouvé."
else
  echo "Volumes EBS détachés:"
  echo "$DETACHED_VOLS" | while read VOL_ID SIZE TYPE CREATE_TIME; do
    echo "  - $VOL_ID (${SIZE}GB $TYPE, créé le $CREATE_TIME)"
    if $EXECUTE; then
      # Créer un snapshot avant suppression
      SNAP=$(aws ec2 create-snapshot --volume-id $VOL_ID \
        --description "Pre-delete backup $(date +%Y%m%d)" \
        --query 'SnapshotId' --output text --region $REGION)
      echo "    → Snapshot créé: $SNAP"
      aws ec2 delete-volume --volume-id $VOL_ID --region $REGION
      echo "    → Volume supprimé"
    fi
  done
fi

echo ""
echo "=== [$DRY_RUN_MSG 3/5] Snapshots EBS > $SNAPSHOT_AGE_DAYS jours ==="
CUTOFF_DATE=$(date -d "-$SNAPSHOT_AGE_DAYS days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
              date -v-${SNAPSHOT_AGE_DAYS}d +%Y-%m-%dT%H:%M:%SZ)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

OLD_SNAPS=$(aws ec2 describe-snapshots \
  --owner-ids $ACCOUNT \
  --query "Snapshots[?StartTime<='$CUTOFF_DATE'].[SnapshotId,VolumeSize,StartTime,Description]" \
  --output text --region $REGION)

if [[ -z "$OLD_SNAPS" ]]; then
  echo "Aucun snapshot ancien trouvé."
else
  echo "Snapshots > $SNAPSHOT_AGE_DAYS jours:"
  echo "$OLD_SNAPS" | while read SNAP_ID SIZE START_TIME DESC; do
    echo "  - $SNAP_ID (${SIZE}GB, $START_TIME) - $DESC"
    if $EXECUTE; then
      aws ec2 delete-snapshot --snapshot-id $SNAP_ID --region $REGION
      echo "    → Supprimé"
    fi
  done
fi

echo ""
echo "=== [$DRY_RUN_MSG 4/5] Load Balancers sans targets ==="
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName]' \
  --output text --region $REGION | while read LB_ARN LB_NAME; do
  TARGETS=$(aws elbv2 describe-target-groups --load-balancer-arn $LB_ARN \
    --query 'TargetGroups[*].TargetGroupArn' --output text 2>/dev/null || echo "")
  if [[ -z "$TARGETS" ]]; then
    echo "  - ALB sans target groups: $LB_NAME"
    if $EXECUTE; then
      echo "    → Suppression manuelle recommandée (vérifier les listeners d'abord)"
    fi
  fi
done || echo "Aucun ALB à analyser."

echo ""
echo "=== [$DRY_RUN_MSG 5/5] Rapport de coûts (Cost Explorer) ==="
START=$(date -d "-30 days" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)
END=$(date +%Y-%m-%d)
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=SERVICE,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount>`1`].[Keys[0],Metrics.UnblendedCost.Amount,Metrics.UnblendedCost.Unit]' \
  --output table 2>/dev/null || echo "Cost Explorer non disponible (activer dans la console AWS)"

echo ""
echo "=== NETTOYAGE $DRY_RUN_MSG TERMINÉ ==="
if ! $EXECUTE; then
  echo "Relancer avec --execute pour effectuer les suppressions."
fi
