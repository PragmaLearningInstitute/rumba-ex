# Comment RUMBA.EX choisit les exercices

Cette page relie chaque étape du classement à son implémentation. Elle complète l'[article de Pragma Learning Institute sur l'algorithme de sélection](https://pragmalearninginstitute.com/outils/documentation/rumba-ex-algorithme-selection). La référence pour l'API publiée est [`db/recommend.js`](../server/rumba-ex-api/db/recommend.js).

## 1. Transformer les réponses en poids

Pour chaque catégorie `p`, `buildProfileWeights` calcule une moyenne pondérée des réponses :

```text
S[p] = somme(response_value[i] × weight[i]) / somme(weight[i])
c[p] = exp(-S[p] / T) / somme_q exp(-S[q] / T)
```

`response_value` est borné entre 0 et 1, les pondérations entre 0 et 10, et la température `T` entre 0,1 et 3. Sans réponse détaillée, les domaines sélectionnés reçoivent un score identique. Sans aucun domaine exploitable, le code dispose d'une catégorie générale.

Le signe négatif est déterminant : à température constante, une valeur `S` plus faible reçoit davantage de poids. Si vos questions codent « difficulté plus forte » par une valeur plus grande, ne décrivez pas ce calcul comme une priorité automatique aux difficultés les plus fortes. Il faut d'abord définir le sens des réponses et évaluer la convention. Cette documentation décrit le calcul existant ; elle ne lui attribue pas de validité clinique.

Une température basse accentue les différences. Une température haute rapproche les poids. Par exemple, pour `S=[0,1]` et `T=1`, les poids sont environ `[0,731 ; 0,269]`. Aucun tirage aléatoire n'intervient dans cette étape de l'API.

## 2. Constituer les candidats

`fetchExercises` applique la plage d'âge, les exclusions explicites et l'historique du profil. Il lit au plus 250 candidats dans un ordre fondé sur le niveau et le titre. Le classement ne porte donc pas nécessairement sur tout un grand catalogue. L'API écarte également les exercices insuffisamment renseignés et rapproche les doublons par empreinte de texte.

Les similarités précalculées sont lues dans `profile_exercise_similarity`. Plusieurs noms de colonnes historiques sont acceptés. En leur absence, le programme essaie des centroïdes d'embeddings, puis des heuristiques lexicales. Ces solutions de repli n'ont pas la même signification qu'une similarité évaluée sur un corpus de référence.

## 3. Calculer pertinence et diversité

La pertinence est une somme pondérée des similarités, bornée entre 0 et 1 :

```text
R[e] = somme_p c[p] × M[p,e]
F[e] = 0,68 × R[e] + 0,22 × A[e] + 0,10 × D[e]
```

`A` est le score nommé `authority_score` par le code. Il ne constitue pas une certification externe de la qualité de l'exercice. Pour connaître sa construction exacte et les valeurs de repli, consulter `buildCandidateScores` dans la version du code utilisée.

`selectWithMmr` sélectionne un exercice, recalcule la diversité des candidats restants par rapport aux exercices déjà choisis, puis continue. Avec des embeddings, la diversité repose sur une distance cosinus. Sans vecteurs, elle repose sur les domaines : deux exercices du même domaine reçoivent une distance plus faible. Le premier exercice reçoit une diversité initiale de 1.

Cette procédure cherche une liste pertinente et moins redondante. Elle ne garantit ni une diversité optimale globale, ni un ordre pédagogique progressif. Les coefficients 0,68/0,22/0,10 sont des paramètres de conception à tester.

## 4. Incorporer les retours

L'application peut enregistrer une note sur 20 et une facilité ressentie de 1 à 5. `feedbackBiasForExercise` utilise ces retours par domaine pour infléchir le choix du niveau. Des seuils comme une note inférieure à 10 ou une facilité faible déclenchent des ajustements codés explicitement.

Un retour isolé peut refléter le contexte, la fatigue, une consigne ambiguë ou un exercice mal conçu. Il ne faut pas interpréter cette adaptation heuristique comme l'apprentissage d'un modèle clinique. Contrôler les données manquantes, leur conversion numérique et le volume de retours avant toute analyse comparative.

## 5. Comprendre les variantes

| Variante | Source | Particularité |
| --- | --- | --- |
| API | `server/rumba-ex-api/db/recommend.js` | Catalogue PostgreSQL, exclusions, similarités et reranking |
| Navigateur en secours | `web/rumba-ex-app.html` | Exercices embarqués et règles locales |
| SwiftUI | `desktop/macos/Sources/RumbaMacApp/` | Services et mathématiques natifs, catalogue local optionnel |

Le nom `rumbaEngine.js` peut prêter à confusion : ce fichier partagé est principalement le moteur de **formatage de lecture**, également utilisé par RUMBA.RD. La recommandation EX de l'API réside dans `db/recommend.js`.

## Limites et interprétation

Les catégories du logiciel sont des étiquettes opérationnelles du catalogue. Les observations saisies ne posent pas un diagnostic. Une similarité sémantique n'est pas une preuve d'adéquation pédagogique, et le score final n'est pas une probabilité calibrée. Une validation sérieuse doit examiner séparément qualité des exercices, accord des professionnels, réussite aux tâches, compréhension et effets sur différents groupes.

Pour reproduire une sélection, archiver le commit, les paramètres, l'état du catalogue, les vecteurs, les exclusions et les retours utilisés. Publier uniquement des données synthétiques ou une analyse agrégée suffisamment protégée. Le [toolkit oculométrique](https://github.com/PragmaLearningInstitute/reading-eye-tracking-toolkit) permet d'étudier un autre aspect — la lecture — mais ses mesures ne valident pas à elles seules ce classement d'exercices.
