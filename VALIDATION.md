# Validation de l'édition publique

Vérifications effectuées le 28 septembre 2026 sur la copie de publication. Les sources de production n'ont pas été modifiées.

## Vérifié

- Parcours navigateur invité vérifié : profil fictif, génération de trois exercices locaux et message explicite de secours.
- Deux tests du limiteur HTTP : un en-tête transmis ne change pas l'identité limitée ; capacité bornée et récupération après expiration.
- Syntaxe des fichiers JavaScript, Python et Swift. L'analyse syntaxique Swift ne constitue pas une compilation complète.
- Installation verrouillée de l'API et du worker ; `npm audit --omit=dev` ne signale aucune vulnérabilité connue au moment du contrôle.
- Démarrage de l'API sur localhost avec une instance PostgreSQL temporaire isolée et le catalogue fictif : deux recommandations retournées, âge invalide refusé, profil sauvegardé refusé à un invité, inscription désactivée, page web servie et fichier caché non exposé.
- Lecture des fichiers de configuration publiés et recherche de motifs de clés, jetons, mots de passe intégrés aux URL et chemins personnels.

## Limites

L'audit de sécurité des sources est partiel. Aucun test complet de l'instance Directus, aucune étude de résistance en production, aucun calcul ML avec téléchargement du modèle ni compilation/signature complète de l'application macOS n'ont été réalisés dans cette validation. Les archives HTML ne sont pas un site autonome. Le fonctionnement d'un CDN et d'une bibliothèque d'export dépend du réseau et du navigateur.

Le catalogue de trois exemples est fictif. Il sert à vérifier le démarrage et les contrats, pas la qualité pédagogique ou une performance de recommandation. Des défauts peuvent subsister malgré ces contrôles.
