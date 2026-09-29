# Utiliser RUMBA.EX : du premier essai à un environnement de développement

RUMBA.EX prépare des exercices à partir de paramètres choisis par l'utilisateur. Il permet d'examiner une proposition, ses indices et sa réponse attendue, puis de l'exporter. Cette page décrit les sources présentes dans ce dépôt. Pour utiliser directement le service hébergé, ouvrir [RUMBA.EX sur le site de Pragma Learning Institute](https://pragmalearninginstitute.com/rumba-ex).

## Choisir son mode

| Besoin | Mode conseillé | Dépendances |
| --- | --- | --- |
| Examiner le parcours et les exports | Navigateur, invité | Serveur HTTP local Python |
| Étudier les recommandations du catalogue | API | Node.js, PostgreSQL, schéma et exercices |
| Enregistrer des profils avec des droits par compte | API + Directus | Instance Directus configurée et testée |
| Développer l'application native | SwiftUI | macOS, Swift 6/Xcode, dépendances Swift |
| Recalculer les représentations sémantiques | Pipeline Python | Environnement scientifique, modèle, PostgreSQL |

Ces modes ne produisent pas nécessairement les mêmes exercices : ils n'utilisent ni le même catalogue ni exactement le même calcul. Toujours consigner le mode dans une évaluation.

## Premier essai sans compte

À la racine du dépôt :

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory web
```

Ouvrir `http://127.0.0.1:8080/rumba-ex-app.html`. Utiliser un identifiant fictif, par exemple `DEMO-01`, et choisir l'accès invité. Renseigner l'âge, les domaines de difficulté, le nombre d'exercices et les observations proposées. Le code limite l'âge à 6–14 ans et les demandes à 1–5 exercices ; il s'agit de bornes logicielles, pas d'une validation d'usage pour chaque âge.

Après génération, lire le contenu, l'indice et la réponse attendue. Vérifier leur cohérence avec l'objectif pédagogique. Une étoile ou un pourcentage représente le score interne de classement ; ce n'est pas une probabilité de réussite. Modifier la police et la taille avant l'export. Commencer par HTML, qui ne nécessite pas le chargement des bibliothèques d'export PDF/DOCX.

Lorsque le serveur n'est pas disponible, un message signale l'utilisation du catalogue local. C'est le résultat attendu du démarrage rapide. Pour contrôler la recommandation PostgreSQL, lancer l'API décrite ci-dessous.

## API et catalogue de développement

Utiliser une base de développement dédiée. Le schéma `schema/000_development.sql` fournit des exemples fictifs et les colonnes consommées par l'API. Il ne constitue pas une migration de votre base de production.

```bash
createdb rumba_dev
psql -v ON_ERROR_STOP=1 -d rumba_dev -f schema/000_development.sql
cd server/rumba-ex-api
npm ci
PGDATABASE=rumba_dev PGUSER="$(id -un)" HOST=127.0.0.1 PORT=3001 npm start
```

Adapter l'authentification PostgreSQL à votre poste. Ne recopier aucun mot de passe d'exemple. L'API invitée peut être essayée sans Directus :

```bash
curl --fail-with-body http://127.0.0.1:3001/rumba-ex/api/recommend \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer guest' \
  --data '{"age":9,"blockers":["phonologique"],"exercise_target":2,"temperature":0.8}'
```

La réponse est un tableau d'exercices avec `exercise_id`, `title`, `content`, `hint`, `correct_answer` et les scores. Un tableau vide est possible si aucun exercice ne satisfait les contraintes ou si tous ont déjà été exclus.

Pour une interface et une API sur la même origine, utiliser `SERVE_WEB=true` au démarrage de l'API, puis ouvrir `http://127.0.0.1:3001/rumba-ex-app.html`. Les comptes demandent en plus Directus, ses collections et ses politiques de propriété. Voir le [contrat d'authentification](deployment.fr.md).

## Application macOS

Le code natif utilise SwiftUI et Swift Package Manager :

```bash
cd desktop/macos
swift build
RUMBA_ENABLE_LOCAL_FALLBACK=true swift run RumbaMacApp
```

Le mode de secours local doit être activé explicitement. Il utilise le catalogue embarqué lorsque PostgreSQL est indisponible. Le sélecteur de profils par nom est un outil local de sélection, pas un mécanisme d'authentification entre plusieurs personnes. Employer des pseudonymes sur un poste de recherche protégé.

Pour connecter PostgreSQL, définir `RUMBA_DB_HOST`, `RUMBA_DB_PORT`, `RUMBA_DB_USER`, `RUMBA_DB_PASSWORD` si nécessaire, `RUMBA_DB_NAME` et `RUMBA_DB_TLS`. Le mode TLS exige une connexion chiffrée lorsqu'il est activé. L'application stocke son secours local dans `Application Support/RumbaMacApp/local_backend.json` sous le compte utilisateur.

## Résoudre les problèmes courants

| Symptôme | Vérification utile |
| --- | --- |
| Le fichier HTML ouvert par double-clic échoue | Utiliser le serveur HTTP local ; les modules sont soumis aux règles d'origine du navigateur |
| L'interface utilise le catalogue de secours | Vérifier l'API et la route `/rumba-ex/api/health` |
| Une demande de profil retourne 401 | Vérifier le jeton Directus et sa validité |
| Une suppression retourne 403 | Vérifier le propriétaire du profil et les politiques Directus |
| Les exports PDF/DOCX échouent | Vérifier l'accès aux CDN ou utiliser HTML ; préférer les dépendances locales pour un déploiement isolé |
| Swift ne compile pas | Vérifier Swift 6, les outils Xcode et la résolution des paquets |
| Le pipeline ne trouve pas d'embeddings | Vérifier le catalogue, le modèle et la dimension 384 |

Avant de comparer deux résultats, conserver la version du code, les paramètres, le catalogue utilisé et l'état des embeddings. Un changement de données peut modifier la sélection sans changement du programme.
