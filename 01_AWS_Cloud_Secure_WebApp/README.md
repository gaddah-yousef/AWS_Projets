# 01 - AWS Cloud Secure Web Application

## Description
Déploiement complet d'une application web sécurisée sur AWS avec VPC isolé, EC2 en Auto Scaling, RDS (MySQL), Application Load Balancer, WAF et HTTPS via ACM.

## Architecture
```
Internet → ALB (HTTPS/443) → WAF → EC2 Auto Scaling Group (Private Subnet) → RDS MySQL (Private Subnet)
                                      ↑
                              NAT Gateway (Public Subnet)
```

## Composants déployés
| Composant | Détail |
|---|---|
| VPC | 10.0.0.0/16, 2 AZ |
| Subnets | 2 public + 2 private |
| IGW + NAT | Internet Gateway + NAT Gateway |
| EC2 | t3.micro, Amazon Linux 2, Nginx |
| ALB | HTTPS, ACM Certificate |
| RDS | MySQL 8.0, Multi-AZ |
| WAF | Règles OWASP Top 10 |
| Security Groups | Least privilege |

## Prérequis
- AWS CLI configuré (`aws configure`)
- Paire de clés SSH existante
- Certificat ACM ou domaine Route53

## Utilisation
```bash
# 1. Créer le VPC et réseau
chmod +x scripts/setup_vpc.sh && ./scripts/setup_vpc.sh

# 2. Déployer EC2 + ALB
chmod +x scripts/deploy_ec2.sh && ./scripts/deploy_ec2.sh

# 3. Créer la base de données
chmod +x scripts/setup_rds.sh && ./scripts/setup_rds.sh

# 4. Configurer WAF
chmod +x scripts/setup_waf.sh && ./scripts/setup_waf.sh

# 5. Configurer HTTPS
chmod +x scripts/setup_alb_https.sh && ./scripts/setup_alb_https.sh
```

## Sécurité appliquée
- Chiffrement EBS + RDS at rest (KMS)
- HTTPS forcé (redirection HTTP → HTTPS)
- Security Groups restrictifs (least privilege)
- WAF avec règles OWASP
- VPC Flow Logs activés
- S3 access logs pour ALB
- Rotation automatique des credentials RDS via Secrets Manager
