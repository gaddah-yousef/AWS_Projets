# Lab 03 — AWS Site-to-Site VPN (Hybrid Networking)

**Goal:** study the configuration of an IPsec site-to-site VPN between an authorized on-premises network and a lab AWS VPC.

> This lab creates **billable VPN resources** and requires real customer-gateway and VPC identifiers. It does not automatically configure a Cisco/Fortinet/pfSense device, establish a tunnel or prove working end-to-end routing.

## Architecture

```text
Authorized on-prem network (192.168.0.0/24)
           |
     Customer Gateway
           |
   IPsec/IKEv2 VPN tunnels
           |
   AWS Virtual Private Gateway
           |
   Lab VPC private route tables
```

## Scripts

- `scripts/setup_vpn.sh` — creates VGW, CGW, two AWS VPN tunnels, **static route** and route propagation; asks for explicit cost confirmation.
- `scripts/download_vpn_config.sh` — securely saves an **existing VPN** customer configuration XML with filesystem mode 600; fails if target file already exists.

## Preflight

```bash
aws sts get-caller-identity
export AWS_REGION=us-east-1
export CUSTOMER_IP=REPLACE-WITH-PUBLIC-ONPREM-GATEWAY-IP
export VPC_ID=vpc-REPLACE
export PRIV_RT_ID=rtb-REPLACE
export ONPREM_CIDR=192.168.0.0/24
```

Use correct identifiers for a **VPC you own**. Review allowed encryption and IKE policies with your on-prem VPN vendor.

## Deployment

```bash
bash scripts/setup_vpn.sh
```

The setup creates the AWS resource but **tunnels remain down** until the other side is configured. Note the printed VPN ID.

To download/refresh its device configuration separately:

```bash
export VPN_ID=vpn-REPLACE
bash scripts/download_vpn_config.sh
```

The resulting XML can include **sensitive pre-shared keys**. Do not check it into Git, send it over unsecured channels or include it in public portfolio screenshots.

## Validation

```bash
aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID" \
  --query 'VpnConnections[0].VgwTelemetry' --output table
```

Observe both tunnel states, routes, security groups, firewalls and test traffic under authorization. The provided configuration uses **static routing**; ASN fields are illustrative and do not mean BGP is enabled.

## Next engineering steps

Add automated AWS validation, device-specific runbooks, managed secret handling, tunnel monitoring and a documented teardown.

**Skills:** hybrid cloud security, IPsec, IKEv2, routing, AWS gateway components.
