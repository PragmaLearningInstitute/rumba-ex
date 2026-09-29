# Ajouter des exercices et déclencher le pipeline

Depuis `server/`, installer les dépendances Node avec `npm ci` et les dépendances Python dans un environnement virtuel avec `pip install -r requirements-ml.txt`. Configurer une base de développement dédiée ; les secrets restent dans l'environnement, hors de Git.

```bash
export RUMBA_DB_URL="postgresql://localhost/rumba_dev"
psql -v ON_ERROR_STOP=1 "$RUMBA_DB_URL" -f trigger_ml_notify.sql
npm start
```

Le trigger `rumba_exercise_changed` invalide l'embedding lors de la création d'un exercice ou d'une modification du titre/contenu et envoie une notification `exercise_changed`. Le worker attend une période sans notification, 60 secondes par défaut, puis lance le pipeline. Le calcul des embeddings ne réécrit pas le titre ou le contenu et ne relance donc pas ce trigger.

## Exemple fictif d'insertion

```sql
INSERT INTO exercise (exercise_id, title, content, domain, level, age_min, age_max, correct_answer, hint)
VALUES (gen_random_uuid(), 'Repérer un son',
        'Dans bateau, quel son entends-tu au début ?',
        'Phonémique', 'Niveau1', 6, 10, 'Le son b.',
        'Prononce lentement le mot.');
```

Vérifier ensuite `embedding_needs_sync` et `embedding_updated_at` pour cet identifiant. La réussite du pipeline dépend de pgvector, du modèle et des colonnes configurées ; lire les journaux en cas d'échec. Une notification seule ne garantit pas le succès du calcul.

## Exécution supervisée

Le fichier `rumba-ex-worker.ecosystem.config.cjs` peut être utilisé avec une installation PM2 existante. Le script `rumba-ex-ml-cron.sh` est une autre entrée pour un planificateur ; choisir une stratégie qui évite des recalculs concurrents. Les journaux restent dans le dossier serveur sauf configuration explicite de leurs chemins.

## Intégration Directus

Une instance Directus peut exposer le catalogue PostgreSQL avec un rôle d'édition dédié et des permissions adaptées. Le pipeline dispose de paramètres de synchronisation documentés dans [le guide des embeddings](../docs/embeddings.fr.md). Tester toute automatisation sur une instance distincte.

Les anciennes notes proposaient un Flow vers une route `/api/admin/import-exercise`. Cette route d'import n'est pas implémentée dans l'API autonome publiée : ne pas considérer cet ancien exemple de Flow comme une fonctionnalité disponible. Une future route exige authentification administrative, validation du contenu, requêtes paramétrées et tests de permissions.

Voir [le guide de déploiement](../docs/deployment.fr.md) pour les contrats et les différences entre schémas natif et Directus.
