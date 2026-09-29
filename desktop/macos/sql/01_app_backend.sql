-- App-specific backend schema for profile isolation, diagnostics and history.
-- Run after schema/000_development.sql and schema/001_embeddings.sql.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Normalize uuid_generate_v7 to a safe fallback when custom definitions are broken.
CREATE OR REPLACE FUNCTION uuid_generate_v7() RETURNS uuid AS $$
  SELECT uuid_generate_v4();
$$ LANGUAGE SQL IMMUTABLE;

CREATE TABLE IF NOT EXISTS student_profile (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    student_name TEXT NOT NULL UNIQUE,
    age INTEGER NOT NULL CHECK (age BETWEEN 6 AND 14),
    blockers dyslexia_type_enum[] NOT NULL,
    exercise_target INTEGER NOT NULL CHECK (exercise_target BETWEEN 1 AND 5),
    temperature DOUBLE PRECISION NOT NULL DEFAULT 0.8,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_set_student_profile_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_student_profile_updated_at ON student_profile;
CREATE TRIGGER trg_student_profile_updated_at
BEFORE UPDATE ON student_profile
FOR EACH ROW EXECUTE FUNCTION trg_set_student_profile_updated_at();

CREATE TABLE IF NOT EXISTS diagnostic_response (
    id BIGSERIAL PRIMARY KEY,
    profile_id UUID NOT NULL REFERENCES student_profile(id) ON DELETE CASCADE,
    dyslexia_type dyslexia_type_enum NOT NULL,
    item_prompt TEXT NOT NULL,
    response_value DOUBLE PRECISION NOT NULL CHECK (response_value BETWEEN 0 AND 1),
    weight DOUBLE PRECISION NOT NULL CHECK (weight > 0),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_diagnostic_response_profile
    ON diagnostic_response(profile_id);

CREATE INDEX IF NOT EXISTS idx_diagnostic_response_profile_type
    ON diagnostic_response(profile_id, dyslexia_type);

CREATE TABLE IF NOT EXISTS profile_recommendation_history (
    profile_id UUID NOT NULL REFERENCES student_profile(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercise(exercise_id) ON DELETE RESTRICT,
    final_score DOUBLE PRECISION NOT NULL,
    relevance_score DOUBLE PRECISION NOT NULL,
    authority_score DOUBLE PRECISION NOT NULL,
    diversity_score DOUBLE PRECISION NOT NULL,
    recommended_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (profile_id, exercise_id)
);

CREATE INDEX IF NOT EXISTS idx_profile_recommendation_history_profile_time
    ON profile_recommendation_history(profile_id, recommended_at DESC);

ALTER TABLE exercise
    ADD COLUMN IF NOT EXISTS embedding_needs_sync BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE exercise
    ADD COLUMN IF NOT EXISTS embedding_updated_at TIMESTAMP;

CREATE OR REPLACE FUNCTION trg_mark_embedding_outdated()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.title IS DISTINCT FROM OLD.title
       OR NEW.content IS DISTINCT FROM OLD.content THEN
        NEW.embedding_needs_sync := TRUE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_mark_embedding_outdated ON exercise;
CREATE TRIGGER trg_mark_embedding_outdated
BEFORE UPDATE OF title, content ON exercise
FOR EACH ROW EXECUTE FUNCTION trg_mark_embedding_outdated();

-- Existing base schema has L2 index. Add cosine index for pgvector cosine query fallback.
-- Some local Postgres setups may not expose ivfflat/vector_cosine_ops.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_am WHERE amname = 'ivfflat')
       AND EXISTS (SELECT 1 FROM pg_opclass WHERE opcname = 'vector_cosine_ops') THEN
        BEGIN
            EXECUTE '
                CREATE INDEX IF NOT EXISTS idx_exercise_embedding_cos
                ON exercise USING ivfflat (embedding vector_cosine_ops)
                WITH (lists = 100);
            ';
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Skipping idx_exercise_embedding_cos creation (%).', SQLERRM;
        END;
    END IF;
END;
$$;
