# Lab 02 — AWS Networking, Peering and Private Endpoints

**Objective:** understand AWS VPC networking by creating two VPCs, a peering connection, subnet route tables, and optionally NAT/service endpoints.

> **Lab notice:** AWS NAT Gateway and interface VPC endpoints incur recurring charges. Use a dedicated test account, inspect the scripts and clean up resources after use.

## Target architecture

```text
VPC A (10.1.0.0/16) --- VPC Peering --- VPC B (10.2.0.0/16)
  |                                             |
  +-- public subnet + IGW                      +-- private subnet
  +-- private subnet
       +-- private S3 gateway endpoint (optional)
       +-- interface endpoints for SSM (optional)
       +-- NAT Gateway for outbound Internet (optional)
```

## Scripts and prerequisites

| Script | Actual functionality |
| --- | --- |
| `scripts/vpc_peering.sh` | Creates two VPCs, subnets, peering and inter-VPC routes |
| `scripts/endpoints.sh` | Adds S3 gateway + SSM/Secrets Manager interface endpoints |
| `scripts/nat_gateway.sh` | Creates a NAT Gateway and a private subnet default route |
| `scripts/test_connectivity.sh` | **Read-only** route, subnet and peering-state inspection |

**Note:** Transit Gateway is a conceptual comparison topic, **not** a deployed component in this repository. `test_connectivity.sh` does not generate live ICMP/TCP probes or prove full connectivity.

```bash
aws sts get-caller-identity
export AWS_DEFAULT_REGION=us-east-1
bash scripts/vpc_peering.sh
bash scripts/test_connectivity.sh
```

Optional, **cost-bearing** components:

```bash
bash scripts/endpoints.sh
bash scripts/nat_gateway.sh
```

The scripts share resource IDs in `/tmp/networking_ids.env`. Ensure your AWS CLI default region matches the configured lab region before running **any** stage.

## Validation and troubleshooting

To establish actual connectivity, deploy dedicated test hosts in each subnet, validate NACLs and Security Groups, then perform authorized ICMP/TCP checks from one host to the other.

Verify the peering connection is `active`, both sides have correct routes, and that a VPC peering relationship is **nontransitive**.

## Security and cost limits

- Gateway endpoints for S3 and interface endpoints have different cost and routing models.
- NAT Gateway may incur both hourly and data processing charges.
- Private subnet placement alone does not guarantee least privilege.
- No account-wide deployment or teardown was executed during this documentation change.

**Skills:** CIDR design, route tables, VPC peering, endpoints, NAT egress, private subnet security.
