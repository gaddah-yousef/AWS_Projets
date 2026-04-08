# 02 - AWS Networking Lab

## Description
Lab complet d'infrastructure réseau AWS : VPC Peering, NAT Gateway, VPC Endpoints (S3, SSM), Transit Gateway et configuration avancée des route tables.

## Architecture
```
VPC-A (10.1.0.0/16) ←──── Peering ────→ VPC-B (10.2.0.0/16)
      ↓                                         ↓
NAT Gateway                              VPC Endpoint S3
(accès Internet)                         (accès privé S3)
      ↓
VPC Endpoint SSM
(sans Internet pour EC2)
```

## Composants
| Composant | Description |
|---|---|
| VPC Peering | Connexion entre VPC-A et VPC-B |
| NAT Gateway | Accès Internet pour subnets privés |
| VPC Endpoint S3 | Accès S3 sans Internet |
| VPC Endpoint SSM | Session Manager sans bastion |
| Route Tables | Routes inter-VPC et endpoints |

## Utilisation
```bash
chmod +x scripts/*.sh
./scripts/vpc_peering.sh      # Crée VPC + Peering
./scripts/endpoints.sh        # Crée VPC Endpoints
./scripts/nat_gateway.sh      # Configure NAT Gateway
./scripts/test_connectivity.sh # Teste la connectivité
```

## Objectifs pédagogiques
- Comprendre le routage AWS (route tables)
- Différence VPC Peering vs Transit Gateway
- Optimisation des coûts réseau (endpoints = pas de NAT pour S3)
- Accès sécurisé EC2 sans bastion via SSM
