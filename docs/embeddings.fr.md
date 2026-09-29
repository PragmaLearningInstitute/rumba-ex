# Embeddings, groupes d'exercices et projection : ce que calcule le pipeline

Le pipeline [`rumba_ml_pipeline.py`](../server/rumba_ml_pipeline.py) transforme le titre et le contenu des exercices en vecteurs, calcule des proximités et prépare des métadonnées de visualisation. Il complète la [documentation PLI sur les embeddings](https://pragmalearninginstitute.com/outils/documentation/rumba-ex-embeddings-exercices).

## Entrées et sorties

L'entrée principale est la table `exercise`, avec un identifiant, un titre, un contenu et un embedding. Le modèle par défaut est `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`. Le code attend des vecteurs de dimension 384. Changer `RUMBA_ML_MODEL` ne suffit donc pas si le nouveau modèle produit une autre dimension : il faut adapter et migrer le schéma ainsi que les contrôles.

Les représentations sont calculées sur `title + content`. Les lignes sans embedding ou marquées comme obsolètes sont candidates à la mise à jour. Les vecteurs existants sont normalisés avant les calculs suivants.

| Sortie | Méthode | Interprétation |
| --- | --- | --- |
| `profile_exercise_similarity` | Similarité cosinus | Proximité vectorielle profil–exercice |
| `cluster_id`, `cluster_label` | HDBSCAN | Groupes exploratoires ; `-1` indique du bruit |
| `umap_x`, `umap_y` | UMAP | Projection en deux dimensions pour explorer le catalogue |
| `nearest_neighbors` | Proximité entre vecteurs | Exercices voisins dans l'espace de représentation |
| `last_ml_run` | Horodatage | Fraîcheur de la dernière synchronisation |

Les libellés de groupes sont construits à partir des domaines et niveaux dominants. Ils ne sont pas des classes pédagogiques découvertes et validées automatiquement.

## PCA et UMAP : éviter une confusion de version

Une [page historique PLI présente une approche PCA](https://pragmalearninginstitute.com/outils/documentation/rumba-ex-pca-recommandation). Dans le pipeline Python publié ici, la projection effectivement appelée est **UMAP**, et le regroupement est **HDBSCAN**. Aucune exécution de PCA ne doit être déduite du titre de cette page historique. La documentation de provenance conserve ce rapprochement pour comprendre l'évolution du projet.

Une projection 2D déforme les distances. Deux points proches dans le graphique ne démontrent pas que les exercices ont le même effet sur un apprenant. Le moteur de recommandation doit utiliser les représentations et règles prévues, pas une lecture visuelle de la carte UMAP.

## Installer et exécuter

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-ml.txt
export RUMBA_DB_URL='postgresql://localhost/rumba_dev'
python rumba_ml_pipeline.py --dry-run --skip-directus
```

Le premier chargement du modèle peut télécharger ses fichiers. Pour une exécution isolée, préparer un modèle local et définir `RUMBA_ML_MODEL` vers son répertoire. Les textes d'exercices sont encodés par le modèle chargé dans le processus ; aucune API de génération externe n'est requise par ce pipeline.

`--dry-run` vérifie et analyse les embeddings **déjà disponibles** ; il ne calcule pas les embeddings manquants. Après validation sur une base de développement :

```bash
python rumba_ml_pipeline.py --skip-directus --batch-size 32
```

Cette commande écrit dans PostgreSQL. Sans `--skip-directus`, elle met aussi à jour les métadonnées dans l'instance Directus explicitement configurée. Utiliser un compte de service limité aux collections nécessaires. Ne jamais exposer le jeton de ce service dans le navigateur.

## Cas limites à connaître

HDBSCAN est ignoré pour moins de cinq exercices. UMAP utilise une stratégie adaptée aux très petits ensembles dans le code. Un corpus vide provoque un arrêt sans recommandations à calculer. Si aucun vecteur de profil compatible n'est disponible, des centroïdes par domaine ou un centroïde global servent de secours. Ce secours doit être consigné dans les comptes rendus.

La compatibilité des champs `learnerprofile` dépend des noms reconnus par `detect_learner_profile_columns`. Une ancienne base peut employer `profil_learner_embedding` : vérifier explicitement le schéma et la version, au lieu de supposer que tout vecteur présent est utilisé.

## Mettre à jour après modification d'un exercice

Le worker [`rumba-ex-ml-worker.js`](../server/rumba-ex-ml-worker.js) écoute un canal PostgreSQL, regroupe les notifications et lance le processus Python. Le délai par défaut est de 60 secondes. Le script de déclenchement fourni dans le dépôt marque les embeddings obsolètes et notifie ce canal ; il doit être installé sur votre base dédiée.

Pour reproduire une exécution, enregistrer le commit, la version du modèle, les versions des bibliothèques, le corpus, les paramètres, les graines réellement utilisées et les dimensions des vecteurs. Les métadonnées 2D sont exploratoires. Une évaluation de la pertinence doit utiliser des annotations ou critères indépendants de l'embedding qui a produit le classement.
