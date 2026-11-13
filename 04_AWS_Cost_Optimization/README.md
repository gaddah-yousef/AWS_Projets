# Lab 04 — AWS Cost Optimization & Safe Resource Review

**Purpose:** demonstrate AWS FinOps concepts with **read-only cost reports**, a project-scoped cleanup review, sample Spot capacity and an opt-in S3 lifecycle rule.

> AWS costs and discounts change frequently. No hardcoded dollar amount in a script is a current quote. Some commands create resources and may increase spending. Inspect scripts before execution.

## Contents

| Script | Behavior | Safety |
| --- | --- | --- |
| `scripts/cost_analysis.sh` | Reads recent AWS Cost Explorer spending by service | Read-only |
| `scripts/cost_report.sh` | Exports daily cost history to CSV | Read-only; refuses overwrite |
| `scripts/cost_cleanup.sh` | Lists unused resources scoped by the `Project` tag | Dry-run by default |
| `scripts/s3_lifecycle.sh` | Previews an S3 transition-to-Standard-IA policy | Dry-run unless `--apply` |
| `scripts/spot_instances.sh` | Demonstrates mixed On-Demand / Spot Auto Scaling | **Creates billable resources**; review prerequisites |

## Cost visibility

```bash
aws sts get-caller-identity
bash scripts/cost_analysis.sh
OUTPUT_FILE=costs_demo.csv bash scripts/cost_report.sh
```

Requires IAM access and AWS Cost Explorer enablement. The returned costs are reported by AWS; actual invoices and discounts may differ.

## Safe cleanup review

```bash
PROJECT_TAG=MyAwsLab bash scripts/cost_cleanup.sh --dry-run
```

The script considers **only resources tagged `Project=MyAwsLab`**. It lists tagged detached EBS volumes and snapshots for **manual review** and does not delete them.

To opt in to releasing **only unassociated tagged Elastic IPs**:

```bash
PROJECT_TAG=MyAwsLab bash scripts/cost_cleanup.sh --execute
```

You must type a separate confirmation. **Never** run any cleanup script on a shared account without agreeing ownership and retention policies.

## S3 lifecycle (optional)

```bash
BUCKET_NAME=my-lab-bucket PREFIX=lab/ DAYS=90 \
  bash scripts/s3_lifecycle.sh --dry-run
```

Review the preview before `--apply`. Applying the policy changes future object storage classes and costs, not object deletions. If an existing lifecycle is present, overwrite requires explicit additional consent.

## Spot demonstration

`spot_instances.sh` is a **resource provisioning demonstration**, not a live price optimizer. Supply valid AMI/subnet identifiers and review current AWS Spot pricing before running. Spot interruptions must be tolerated by the application.

## Limitations and validation

- Cost Explorer queries are read-only but may incur API charges in some contexts.
- Saving money requires checking current pricing, workload patterns and dependencies.
- No live AWS resources were changed or validated as part of this repository repair.
- Consider Terraform plans, automated tagging, budgets and cost alerts for future labs.

**Skills:** FinOps, AWS billing, safe cleanup, lifecycle policies, Spot capacity and cost governance.
