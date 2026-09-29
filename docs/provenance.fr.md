# Périmètre et provenance de l'édition publique

Cette édition rassemble le code RUMBA.EX extrait des sources du site Pragma Learning Institute et de l'application native RumbaMacApp. Elle fournit une base inspectable pour reproduire le parcours, comprendre le classement et développer une installation indépendante.

## Sources présentes

- Application web, moteur partagé et exporteur, collecteur désactivé par défaut.
- API Express, accès PostgreSQL, contrôle des profils et retours pédagogiques.
- Pipeline Python, worker de notifications, scripts de configuration et schémas.
- Projet Swift Package Manager et projet Xcode, interface, services, dépôts de données et export DOCX.
- Articles historiques HTML dans `docs/original-site/`, conservés comme archives documentaires. Leurs chemins de navigation et ressources de site ne forment pas un site autonome.

Les guides Markdown de `docs/` décrivent l'édition publiée. Les archives ont pu utiliser des termes plus larges que le code : notamment PCA alors que le pipeline actuel utilise UMAP, et une précision pédagogique qui n'a pas valeur de validation clinique. Les explications actuelles relient chaque mécanisme à son fichier source.

## Exclusions de publication

Les secrets, environnements privés, fichiers de comptes, journaux, exports d'apprenants, sauvegardes de bases, dépendances installées et applications compilées ne font pas partie du dépôt. Le catalogue de production est remplacé par trois exercices fictifs. La configuration et les services transversaux du site PLI (comptes, administration, paiement, messagerie) ne sont pas l'application RUMBA.EX autonome.

Aucun moteur natif Windows distinct de RUMBA.EX n'a été identifié dans le lot inspecté. Certains anciens dossiers d'installation Windows contenaient Rumba Reader ; ils ne sont donc pas présentés ici comme une version EX vérifiée. Les polices commerciales ne sont pas redistribuées. Utiliser les polices installées sur le poste selon leurs licences.

## Modifications de publication

Cette édition retire les mots de passe et chemins de poste par défaut, borne la mémoire du limiteur HTTP, restreint la confiance dans les mandataires, désactive les inscriptions sans configuration explicite, impose TLS au client Swift distant et désactive la télémétrie automatique. Les sources de production n'ont pas été modifiées par cette extraction.

La conservation des chiffres et caractères Unicode du moteur de mise en forme partagé a été corrigée. Des tests de régression accompagnent les composants concernés. Consulter `VALIDATION.md` pour les vérifications réellement effectuées et leurs limites.

## Citer et relier les projets

La page institutionnelle est [Pragma Learning Institute](https://pragmalearninginstitute.com/) et le point d'entrée documentaire est [la documentation des outils](https://pragmalearninginstitute.com/outils/documentation). Les liens sont placés à côté des informations qu'ils complètent. Le dépôt fournit un fichier `CITATION.cff` pour identifier le logiciel ; il ne crée ni DOI ni publication scientifique évaluée par les pairs.
