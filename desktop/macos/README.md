# RUMBA.EX pour macOS

Implémentation SwiftUI : profils locaux, recommandation, retour sur les exercices et export DOCX. Swift 6 et macOS 13 minimum sont déclarés dans `Package.swift`.

```bash
swift build
RUMBA_ENABLE_LOCAL_FALLBACK=true swift run RumbaMacApp
```

Le secours local doit être autorisé explicitement. Pour un serveur PostgreSQL, configurer les variables `RUMBA_DB_*` décrites dans le [guide de démarrage](../../docs/getting-started.fr.md).

Sur une base de développement dédiée disposant de pgvector, `RUMBA_DB_URL=postgresql://localhost/rumba_dev bash scripts/bootstrap_db.sh` charge le petit catalogue fictif et le schéma natif. Il ne restaure aucune donnée de production. Les profils sont choisis par leur nom sur le poste : ce sélecteur ne remplace pas une authentification multi-utilisateur. Les connexions distantes exigent TLS et un certificat vérifiable.

Le projet Xcode est également fourni. Les scripts d'installation et de génération du logo sont optionnels ; examiner leur destination avant exécution. Les polices ne sont pas embarquées.
