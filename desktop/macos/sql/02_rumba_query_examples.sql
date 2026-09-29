-- Example SQL snippets for the Rumba recommendation pipeline.
-- Replace bind parameters with your client-side values.

-- 1) Compute weighted error scores S_p for one profile.
WITH sp AS (
    SELECT
        dr.dyslexia_type,
        SUM(dr.response_value * dr.weight) AS error_score
    FROM diagnostic_response dr
    WHERE dr.profile_id = :profile_id
    GROUP BY dr.dyslexia_type
)
SELECT * FROM sp ORDER BY error_score DESC;

-- 2) Build M_p,e from precomputed profile_exercise_similarity (age-filtered).
SELECT
    pes.dyslexia_type,
    pes.exercise_id,
    pes.cosine_sim AS m_pe
FROM profile_exercise_similarity pes
JOIN exercise e ON e.exercise_id = pes.exercise_id
WHERE pes.dyslexia_type = ANY(:selected_blockers)
  AND e.age_min <= :age
  AND e.age_max >= :age;

-- 3) Fallback M_p,e directly from pgvector embeddings if precomputed matrix is missing.
SELECT
    lp.dyslexia_type,
    e.exercise_id,
    (1 - (lp.profil_learner_embedding <=> e.embedding))::double precision AS m_pe
FROM learnerprofile lp
CROSS JOIN exercise e
WHERE lp.dyslexia_type = ANY(:selected_blockers)
  AND lp.profil_learner_embedding IS NOT NULL
  AND e.embedding IS NOT NULL
  AND e.age_min <= :age
  AND e.age_max >= :age;

-- 4) End-to-end relevance R_e and reranking-ready base scores (without diversity loop).
WITH scores AS (
    SELECT
        dr.dyslexia_type,
        SUM(dr.response_value * dr.weight) AS s_p
    FROM diagnostic_response dr
    WHERE dr.profile_id = :profile_id
    GROUP BY dr.dyslexia_type
),
conf AS (
    -- Inverse softmax variant: c_p = exp(-s_p/T) / sum(exp(-s/T))
    SELECT
        s.dyslexia_type,
        EXP(-s.s_p / :temperature) / SUM(EXP(-s.s_p / :temperature)) OVER () AS c_p
    FROM scores s
),
matrix AS (
    SELECT
        pes.dyslexia_type,
        pes.exercise_id,
        pes.cosine_sim AS m_pe
    FROM profile_exercise_similarity pes
    JOIN exercise e ON e.exercise_id = pes.exercise_id
    WHERE pes.dyslexia_type = ANY(:selected_blockers)
      AND e.age_min <= :age
      AND e.age_max >= :age
),
base AS (
    SELECT
        m.exercise_id,
        SUM(c.c_p * m.m_pe) AS r_e,
        AVG(m.m_pe) AS authority_e
    FROM matrix m
    JOIN conf c ON c.dyslexia_type = m.dyslexia_type
    GROUP BY m.exercise_id
)
SELECT
    b.exercise_id,
    b.r_e,
    b.authority_e
FROM base b
WHERE NOT EXISTS (
    SELECT 1
    FROM profile_recommendation_history h
    WHERE h.profile_id = :profile_id
      AND h.exercise_id = b.exercise_id
)
ORDER BY b.r_e DESC
LIMIT :k;
