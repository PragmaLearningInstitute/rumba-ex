-- Fictional development catalogue. No production backup or participant records.
BEGIN;
CREATE TABLE IF NOT EXISTS exercise (
  exercise_id UUID PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
  domain TEXT NOT NULL, level TEXT NOT NULL, age_min INTEGER NOT NULL, age_max INTEGER NOT NULL,
  correct_answer TEXT, hint TEXT, embedding_needs_sync BOOLEAN NOT NULL DEFAULT TRUE,
  embedding_updated_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS profile_exercise_similarity (
  dyslexia_type TEXT NOT NULL, exercise_id UUID NOT NULL REFERENCES exercise(exercise_id),
  cosine_sim DOUBLE PRECISION NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (dyslexia_type, exercise_id)
);
INSERT INTO exercise VALUES
('00000000-0000-4000-8000-000000000001', 'Assembler des syllabes', 'Assemble les syllabes ba et teau. Écris le mot obtenu puis lis-le à voix haute.', 'Phonémique', 'Niveau1',6,14,'bateau','Prononce chaque syllabe avant de les réunir.',TRUE,NULL),
('00000000-0000-4000-8000-000000000002', 'Identifier une information', 'Lina pose le livre sur la table avant de sortir. Où Lina pose-t-elle le livre ? Réponds par une phrase.', 'Comprehension', 'Niveau2',6,14,'Lina pose le livre sur la table.','Cherche le groupe de mots qui indique un lieu.',TRUE,NULL),
('00000000-0000-4000-8000-000000000003', 'Construire une phrase', 'Remets dans l’ordre les mots suivants : jardin / le / dans / joue / enfant / un. Lis ensuite ta phrase.', 'Syntaxe', 'Niveau2',6,14,'Un enfant joue dans le jardin.','Commence par le sujet puis cherche le verbe.',TRUE,NULL)
ON CONFLICT (exercise_id) DO NOTHING;
INSERT INTO profile_exercise_similarity (dyslexia_type, exercise_id, cosine_sim)
SELECT 'phonologique', exercise_id, CASE WHEN domain='Phonémique' THEN 0.8 ELSE 0.4 END FROM exercise
ON CONFLICT DO NOTHING;
COMMIT;
