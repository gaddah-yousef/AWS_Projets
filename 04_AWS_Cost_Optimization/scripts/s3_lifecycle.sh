#!/usr/bin/env bash
# Inspect or explicitly apply an S3 lifecycle transition rule to an owned bucket.
# Does NOT delete objects; applying overrides an existing lifecycle only with extra consent.
set -euo pipefail
: "${BUCKET_NAME:?Export BUCKET_NAME for an owned S3 bucket}"
DAYS="${DAYS:-90}"
PREFIX="${PREFIX:-lab/}"
MODE="${1:---dry-run}"
[[ "$DAYS" =~ ^[0-9]+$ ]] && (( DAYS >= 30 )) || {
  echo "DAYS must be >=30 for Standard-IA transition." >&2; exit 1;
}
[[ "$MODE" == "--dry-run" || "$MODE" == "--apply" ]] || {
  echo "Usage: BUCKET_NAME=name [DAYS=90] [PREFIX=lab/] $0 [--dry-run|--apply]" >&2; exit 2;
}
command -v python3 >/dev/null || { echo "Python 3 required for JSON generation." >&2; exit 1; }
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
BUCKET_NAME="$BUCKET_NAME" DAYS="$DAYS" PREFIX="$PREFIX" python3 - <<'PY' > "$TMP"
import json
import os
print(json.dumps({"Rules": [{"ID": "Lab-Transition-To-StandardIA",
    "Filter": {"Prefix": os.environ["PREFIX"]}, "Status": "Enabled",
    "Transitions": [{"Days": int(os.environ["DAYS"]),
                     "StorageClass": "STANDARD_IA"}]}]}, indent=2))
PY
echo "Proposed S3 lifecycle for bucket $BUCKET_NAME (object deletion NOT configured):"
cat "$TMP"
[[ "$MODE" == "--apply" ]] || { echo "DRY RUN; no change applied."; exit 0; }
if aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET_NAME"   --query Rules --output json >/dev/null 2>&1; then
  [[ "${CONFIRM_REPLACE:-no}" == "yes" ]] || {
    echo "Existing lifecycle detected. Set CONFIRM_REPLACE=yes to replace it." >&2; exit 1;
  }
fi
read -r -p "Type APPLY to change lifecycle of $BUCKET_NAME: " ANSWER
[[ "$ANSWER" == "APPLY" ]] || { echo "Cancelled."; exit 1; }
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET_NAME"   --lifecycle-configuration "file://$TMP"
echo "Lifecycle applied. Review storage class economics and retention requirements."
