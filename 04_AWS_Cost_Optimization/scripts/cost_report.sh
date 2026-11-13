#!/usr/bin/env bash
# Export read-only daily cost data into a CSV suitable for analysis.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
START="$(date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-30d +%Y-%m-%d)"
END="$(date -u +%Y-%m-%d)"
OUTPUT_FILE="${OUTPUT_FILE:-aws_cost_report.csv}"
[[ ! -e "$OUTPUT_FILE" ]] || { echo "File already exists: $OUTPUT_FILE." >&2; exit 1; }
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
aws ce get-cost-and-usage --time-period "Start=$START,End=$END"   --granularity DAILY --metrics UnblendedCost --output json > "$TMP"
python3 - "$TMP" "$OUTPUT_FILE" <<'PY'
import csv
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    raw = json.load(f)
with open(sys.argv[2], "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["date_start", "date_end", "unblended_cost", "currency"])
    for period in raw.get("ResultsByTime", []):
        metric = period["Total"]["UnblendedCost"]
        writer.writerow([period["TimePeriod"]["Start"],
                         period["TimePeriod"]["End"],
                         metric["Amount"], metric["Unit"]])
PY
echo "Cost report saved: $OUTPUT_FILE. Review your AWS invoice for actual charges."
