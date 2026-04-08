# 03 - AWS VPN Site-to-Site

## Description
Configuration d'un VPN Site-to-Site AWS entre un VPC AWS et un réseau on-premise (ou Cisco/Fortinet simulé). Utilise Virtual Private Gateway (VGW) + Customer Gateway (CGW) avec IPSec IKEv2.

## Architecture
```
On-Premise Network          AWS VPC (10.0.0.0/16)
192.168.0.0/24  ←──VPN IPSec IKEv2──→  Virtual Private Gateway
    ↑                                           ↓
Customer Gateway                     Private Subnets
(IP publique: X.X.X.X)              EC2, RDS, etc.
```

## Paramètres IPSec
| Paramètre | Valeur |
|---|---|
| IKE Version | IKEv2 |
| Encryption | AES-256 |
| Integrity | SHA-256 |
| DH Group | Group 14 (2048-bit) |
| Tunnel Protocol | IPSec |
| BGP ASN (AWS) | 64512 |
| BGP ASN (Customer) | 65000 |

## Utilisation
```bash
# 1. Configurer les variables (IP publique on-premise)
export CUSTOMER_IP="X.X.X.X"
export ONPREM_CIDR="192.168.0.0/24"

# 2. Créer VGW + CGW + VPN
chmod +x scripts/setup_vpn.sh && ./scripts/setup_vpn.sh

# 3. Télécharger la configuration pour votre équipement
./scripts/download_vpn_config.sh
```

## Configuration équipement on-premise
Après exécution, télécharger la config AWS et l'appliquer sur :
- Cisco ASA / IOS
- Fortinet FortiGate
- pfSense / OPNSense
- StrongSwan (Linux)
