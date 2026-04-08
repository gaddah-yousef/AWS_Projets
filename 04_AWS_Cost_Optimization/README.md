# 04 - AWS Cost Optimization

## Description
Stratégies et scripts d'optimisation des coûts AWS : nettoyage des ressources inutilisées, Savings Plans, Spot Instances, rightsizing EC2, et rapport de coûts automatique.

## Stratégies couvertes
| Stratégie | Économie estimée |
|---|---|
| Suppression EIP non utilisées | 3.60$/mois/EIP |
| Arrêt instances hors heures | 60-70% sur EC2 |
| Spot Instances | jusqu'à 90% vs On-Demand |
| RDS Snapshots anciens | Variable |
| S3 Lifecycle Policies | 40-60% sur stockage |
| Rightsizing EC2 | 20-40% |
| Reserved Instances 1an | 30-40% |

## Utilisation
```bash
# Analyser les coûts (dry-run, aucune suppression)
./scripts/cost_analysis.sh

# Nettoyage des ressources inutilisées (avec confirmation)
./scripts/cost_cleanup.sh

# Configurer les politiques S3 Lifecycle
./scripts/s3_lifecycle.sh

# Déployer des Spot Instances pour les workloads non-critiques
./scripts/spot_instances.sh

# Rapport mensuel des coûts
./scripts/cost_report.sh
```

## Sécurité
Tous les scripts font un dry-run par défaut. Passer `--execute` pour confirmer les suppressions.
