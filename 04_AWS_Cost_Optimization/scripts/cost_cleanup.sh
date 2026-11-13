#!/usr/bin/env bash
# Safety-first AWS cleanup review.
# Default: read-only. --execute can ONLY release unassociated Elastic IPs tagged
# with the supplied Project value. No EBS volume or snapshot is auto-deleted.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
MODE="${1:---dry-run}"
TAG="${PROJECT_TAG:-}"
[[ "$MODE" == "--dry-run" || "$MODE" == "--execute" ]] || {
  echo "Usage: PROJECT_TAG=YourLab $0 [--dry-run|--execute]" >&2; exit 2;
}
[[ -n "$TAG" ]] || {
  echo "PROJECT_TAG is required to prevent affecting unrelated resources." >&2; exit 2;
}
echo "Account $(aws sts get-caller-identity --query Account --output text)"
echo "Region $AWS_DEFAULT_REGION, project tag $TAG, mode $MODE"

echo "--- Unassociated Elastic IPs (Project=$TAG) ---"
ALLOCATIONS="$(aws ec2 describe-addresses \
  --filters "Name=tag:Project,Values=$TAG" \
  --query 'Addresses[?AssociationId==`null`].AllocationId' \
  --output text)"
if [[ -z "$ALLOCATIONS" || "$ALLOCATIONS" == "None" ]]; then
  echo "None found"
else
  printf '%s\n' "$ALLOCATIONS"
fi

echo "--- Detached volumes: manual inspection only ---"
aws ec2 describe-volumes --filters \
  "Name=tag:Project,Values=$TAG" "Name=status,Values=available" \
  --query 'Volumes[*].[VolumeId,Size,CreateTime]' --output table

echo "--- Owned snapshots: manual inspection only ---"
aws ec2 describe-snapshots --owner-ids self \
  --filters "Name=tag:Project,Values=$TAG" \
  --query 'Snapshots[*].[SnapshotId,StartTime,VolumeSize]' --output table

if [[ "$MODE" != "--execute" ]]; then
  echo "DRY RUN. No AWS resources modified."
  exit 0
fi
[[ -n "$ALLOCATIONS" && "$ALLOCATIONS" != "None" ]] || exit 0
read -r -p "Type RELEASE-IP to release ONLY the listed unused Project-tagged EIPs: " CONFIRM
[[ "$CONFIRM" == "RELEASE-IP" ]] || { echo "Cancelled."; exit 1; }
for ALLOCATION_ID in $ALLOCATIONS; do
  aws ec2 release-address --allocation-id "$ALLOCATION_ID"
  echo "Released: $ALLOCATION_ID"
done
echo "No volumes or snapshots were deleted. Review full account billing separately."
