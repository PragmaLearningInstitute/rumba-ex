-- Optional: install pgvector in PostgreSQL before applying.
CREATE EXTENSION IF NOT EXISTS vector;
ALTER TABLE exercise ADD COLUMN IF NOT EXISTS embedding vector(384);

DO $$ BEGIN
  CREATE TYPE dyslexia_type_enum AS ENUM ('phonologique','RAN','work_memory','visuo_spatiale','oculomoteur','metacognitif','holistique','deep_mixte','double_deficit','M_type','neurocognitig_multiple');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE TABLE IF NOT EXISTS learnerprofile (
 dyslexia_type dyslexia_type_enum PRIMARY KEY,
 profil_learner_embedding vector(384)
);
