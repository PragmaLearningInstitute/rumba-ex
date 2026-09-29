const pool = require("./pool");

const EXERCISE_TABLE = safeIdentifier(process.env.RUMBA_EX_EXERCISE_TABLE || "exercise");
const SIMILARITY_TABLE = safeIdentifier(process.env.RUMBA_EX_SIMILARITY_TABLE || "profile_exercise_similarity");
const HISTORY_TABLES = unique([
  process.env.RUMBA_EX_HISTORY_TABLE,
  "rumba_ex_recommendation_history",
  "profile_recommendation_history"
].filter(Boolean)).map(safeIdentifier);
const SCORE_WEIGHTS = {
  relevance: 0.68,
  authority: 0.22,
  diversity: 0.1
};

async function getRecommendations(input) {
  const target = clampInteger(input.exercise_target, 1, 5, 3);
  const age = clampInteger(input.age, 6, 14, 9);
  const temperature = clampNumber(input.temperature, 0.1, 3, 0.8);
  const profileWeights = buildProfileWeights(input.blockers, input.diagnostic_responses, temperature);
  const requestExcludedIds = Array.isArray(input.exclude_exercise_ids)
    ? input.exclude_exercise_ids.map((value) => String(value || "").trim()).filter(Boolean)
    : [];
  const historyExcludedIds = input.profile_id ? await fetchHistoryExerciseIds(input.profile_id) : [];
  const excludedIds = unique([...historyExcludedIds, ...requestExcludedIds]);
  const exerciseFeedback = mergeFeedbackRows(
    Array.isArray(input.exercise_feedback) ? input.exercise_feedback : [],
    input.profile_id ? await fetchExerciseFeedback(input.profile_id) : []
  );
  const exercises = await fetchExercises(age, excludedIds);

  if (!exercises.length) {
    return [];
  }

  const similarityRows = await fetchSimilarityRows(
    Array.from(profileWeights.keys()),
    exercises.map((exercise) => exercise.exercise_id)
  );
  const candidates = dedupeExerciseCandidates(buildCandidateScores(
    exercises,
    similarityRows,
    profileWeights,
    buildFeedbackSummary(exerciseFeedback)
  ));
  const selected = selectWithMmr(candidates, target);

  return selected.map((candidate) => ({
    exercise_id: candidate.exercise_id,
    title: candidate.title,
    content: candidate.content,
    domain: candidate.domain,
    level: candidate.level,
    age_min: candidate.age_min,
    age_max: candidate.age_max,
    correct_answer: candidate.correct_answer,
    hint: candidate.hint,
    final_score: roundScore(candidate.final_score),
    relevance_score: roundScore(candidate.relevance_score),
    authority_score: roundScore(candidate.authority_score),
    diversity_score: roundScore(candidate.diversity_score)
  }));
}

async function insertRecommendationHistory(profileId, recommendations) {
  if (!profileId || !Array.isArray(recommendations) || recommendations.length === 0) return;

  const values = [];
  const placeholders = [];
  recommendations.forEach((recommendation, index) => {
    const offset = index * 6;
    values.push(
      profileId,
      recommendation.exercise_id,
      recommendation.final_score,
      recommendation.relevance_score,
      recommendation.authority_score,
      recommendation.diversity_score
    );
    placeholders.push(
      `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5}, $${offset + 6}, NOW())`
    );
  });

  await runWithHistoryTable((historyTable) => pool.query(
    `INSERT INTO ${quoteIdent(historyTable)}
        (profile_id, exercise_uuid, final_score, relevance_score, authority_score, diversity_score, recommended_at)
       VALUES ${placeholders.join(", ")}`,
    values
  ));
}

async function resetRecommendationHistory(profileId) {
  await runWithHistoryTable((historyTable) => pool.query(
    `DELETE FROM ${quoteIdent(historyTable)} WHERE profile_id = $1`,
    [profileId]
  ));
}

async function saveExerciseFeedback(profileId, exerciseId, feedback = {}) {
  const note = feedback.note === undefined ? null : feedback.note;
  const ease = feedback.ease === undefined ? null : feedback.ease;

  const result = await runWithHistoryTable((historyTable) => pool.query(
    `UPDATE ${quoteIdent(historyTable)}
        SET student_score = $3,
            student_ease = $4,
            feedback_updated_at = NOW()
      WHERE id = (
        SELECT id
          FROM ${quoteIdent(historyTable)}
         WHERE profile_id = $1
           AND exercise_uuid::text = $2
         ORDER BY recommended_at DESC NULLS LAST
         LIMIT 1
      )`,
    [profileId, exerciseId, note, ease]
  ).catch((error) => {
    if (isMissingColumn(error)) {
      console.warn("[rumba-ex-api] colonnes de feedback absentes de l'historique, retour ignore");
      return { rowCount: 0 };
    }
    throw error;
  }), { allowMissing: true });

  return Boolean(result && result.rowCount > 0);
}

async function fetchHistoryExerciseIds(profileId) {
  const result = await runWithHistoryTable((historyTable) => pool.query(
    `SELECT exercise_uuid::text AS exercise_id FROM ${quoteIdent(historyTable)} WHERE profile_id = $1`,
    [profileId]
  ), { allowMissing: true });
  return result ? result.rows.map((row) => row.exercise_id).filter(Boolean) : [];
}

async function fetchExerciseFeedback(profileId) {
  const result = await runWithHistoryTable((historyTable) => pool.query(
    `SELECT
        h.exercise_uuid::text AS exercise_id,
        h.student_score AS note,
        h.student_ease AS ease,
        h.feedback_updated_at AS updated_at,
        e.domain,
        e.level
       FROM ${quoteIdent(historyTable)} h
       LEFT JOIN ${quoteIdent(EXERCISE_TABLE)} e
         ON e.exercise_id::text = h.exercise_uuid::text
      WHERE h.profile_id = $1
        AND (h.student_score IS NOT NULL OR h.student_ease IS NOT NULL)`,
    [profileId]
  ).catch((error) => {
    if (isMissingColumn(error)) return { rows: [] };
    throw error;
  }), { allowMissing: true });

  return result ? result.rows.map((row) => ({
    exercise_id: row.exercise_id,
    domain: row.domain || null,
    level: row.level === null || row.level === undefined ? null : row.level,
    note: row.note === null || row.note === undefined ? null : Number(row.note),
    ease: row.ease === null || row.ease === undefined ? null : Number(row.ease),
    updated_at: row.updated_at || null
  })) : [];
}

async function fetchExercises(age, excludedIds) {
  const params = [age, excludedIds];
  const baseWhere = `
    WHERE (
      $1::int IS NULL
      OR age_min IS NULL
      OR age_max IS NULL
      OR ($1::int BETWEEN age_min AND age_max)
    )
    AND NOT (exercise_id::text = ANY($2::text[]))
    ORDER BY
      CASE
        WHEN level::text ~ '\\d+' THEN substring(level::text from '\\d+')::int
        ELSE NULL
      END NULLS LAST,
      level::text NULLS LAST,
      title
    LIMIT 250
  `;

  try {
    const result = await pool.query(
      `SELECT
        exercise_id::text AS exercise_id,
        title,
        content,
        domain,
        level,
        age_min,
        age_max,
        correct_answer,
        hint,
        embedding::text AS embedding_text
       FROM ${quoteIdent(EXERCISE_TABLE)}
       ${baseWhere}`,
      params
    );
    return result.rows.map(mapExerciseRow);
  } catch (error) {
    if (!isMissingColumn(error)) throw error;
  }

  const fallback = await pool.query(
    `SELECT
      exercise_id::text AS exercise_id,
      title,
      content,
      domain,
      level,
      age_min,
      age_max,
      correct_answer,
      hint,
      NULL::text AS embedding_text
     FROM ${quoteIdent(EXERCISE_TABLE)}
     ${baseWhere}`,
    params
  );
  return fallback.rows.map(mapExerciseRow);
}

async function fetchSimilarityRows(profileTypes, exerciseIds) {
  if (!profileTypes.length || !exerciseIds.length) return [];

  const variants = [
    {
      sql: `SELECT dyslexia_type::text AS profile, exercise_id::text AS exercise_id, cosine_sim::float AS similarity
            FROM ${quoteIdent(SIMILARITY_TABLE)}
            WHERE dyslexia_type::text = ANY($1::text[]) AND exercise_id::text = ANY($2::text[])`
    },
    {
      sql: `SELECT dyslexia_type::text AS profile, exercise_uuid::text AS exercise_id, similarity::float AS similarity
            FROM ${quoteIdent(SIMILARITY_TABLE)}
            WHERE dyslexia_type::text = ANY($1::text[]) AND exercise_uuid::text = ANY($2::text[])`
    },
    {
      sql: `SELECT profile::text AS profile, exercise_uuid::text AS exercise_id, similarity::float AS similarity
            FROM ${quoteIdent(SIMILARITY_TABLE)}
            WHERE profile::text = ANY($1::text[]) AND exercise_uuid::text = ANY($2::text[])`
    },
    {
      sql: `SELECT profile::text AS profile, exercise_id::text AS exercise_id, similarity::float AS similarity
            FROM ${quoteIdent(SIMILARITY_TABLE)}
            WHERE profile::text = ANY($1::text[]) AND exercise_id::text = ANY($2::text[])`
    },
    {
      sql: `SELECT profile::text AS profile, exercise::text AS exercise_id, sim::float AS similarity
            FROM ${quoteIdent(SIMILARITY_TABLE)}
            WHERE profile::text = ANY($1::text[]) AND exercise::text = ANY($2::text[])`
    }
  ];

  for (const variant of variants) {
    try {
      const result = await pool.query(variant.sql, [profileTypes, exerciseIds]);
      return result.rows
        .map((row) => ({
          profile: normalizeKey(row.profile),
          exercise_id: String(row.exercise_id),
          similarity: clampNumber(row.similarity, 0, 1, 0)
        }))
        .filter((row) => row.profile && row.exercise_id);
    } catch (error) {
      if (!isMissingRelation(error) && !isMissingColumn(error)) throw error;
    }
  }

  console.warn("[rumba-ex-api] table profile_exercise_similarity absente ou incompatible, fallback heuristique utilise");
  return [];
}

function buildCandidateScores(exercises, similarityRows, profileWeights, feedbackSummary = new Map()) {
  const similarityByExercise = new Map();
  const embeddingCentroids = buildEmbeddingCentroids(exercises, profileWeights);

  for (const row of similarityRows) {
    if (!similarityByExercise.has(row.exercise_id)) {
      similarityByExercise.set(row.exercise_id, new Map());
    }
    similarityByExercise.get(row.exercise_id).set(row.profile, row.similarity);
  }

  return exercises.filter(isUsefulExercise).map((exercise) => {
    const profileSimilarities = similarityByExercise.get(exercise.exercise_id) ||
      inferSimilarities(exercise, profileWeights, embeddingCentroids);
    const relevanceScore = clampNumber(
      weightedRelevance(profileSimilarities, profileWeights) + feedbackBiasForExercise(exercise, feedbackSummary),
      0,
      1,
      0
    );
    const authorityScore = average(Array.from(profileSimilarities.values()));

    return {
      ...exercise,
      relevance_score: relevanceScore,
      authority_score: authorityScore || relevanceScore,
      diversity_score: 1,
      final_score: 0
    };
  });
}

function dedupeExerciseCandidates(candidates) {
  const bestByFingerprint = new Map();

  for (const candidate of candidates) {
    const fingerprint = exerciseFingerprint(candidate);
    if (!fingerprint) continue;
    const existing = bestByFingerprint.get(fingerprint);
    if (!existing || baseScore(candidate) > baseScore(existing)) {
      bestByFingerprint.set(fingerprint, candidate);
    }
  }

  return Array.from(bestByFingerprint.values());
}

function isUsefulExercise(exercise) {
  const title = normalizeTextForMatch(exercise && exercise.title);
  const content = normalizeTextForMatch(exercise && exercise.content);
  if (!content || content.length < 40) return false;
  if (title.includes("choisir une strategie et l expliquer")) return false;
  if (content.includes("avant de lire choisis une strategie relire les mots difficiles decouper les phrases ou resumer chaque paragraphe")) return false;
  return true;
}

function exerciseFingerprint(exercise) {
  return normalizeTextForMatch([exercise && exercise.title, exercise && exercise.content].filter(Boolean).join(" ")).slice(0, 260);
}

function mergeFeedbackRows(payloadRows, persistedRows) {
  const merged = new Map();
  for (const row of persistedRows || []) {
    const key = row.exercise_id || `${row.domain || "general"}-${row.updated_at || ""}`;
    merged.set(key, row);
  }
  for (const row of payloadRows || []) {
    const key = row.exercise_id || `${row.domain || "general"}-${row.updated_at || ""}`;
    merged.set(key, row);
  }
  return Array.from(merged.values());
}

function buildFeedbackSummary(rows = []) {
  const summary = new Map();
  for (const row of rows) {
    const domain = row.domain || "general";
    if (!summary.has(domain)) {
      summary.set(domain, {
        count: 0,
        noteSum: 0,
        noteCount: 0,
        easeSum: 0,
        easeCount: 0,
        levelSum: 0,
        levelCount: 0
      });
    }
    const item = summary.get(domain);
    item.count += 1;
    if (Number.isFinite(Number(row.note))) {
      item.noteSum += Number(row.note);
      item.noteCount += 1;
    }
    if (Number.isFinite(Number(row.ease))) {
      item.easeSum += Number(row.ease);
      item.easeCount += 1;
    }
    const level = levelIndex(row.level);
    if (level !== null) {
      item.levelSum += level;
      item.levelCount += 1;
    }
  }
  return summary;
}

function feedbackBiasForExercise(exercise, feedbackSummary) {
  const summary = feedbackSummary.get(exercise.domain || "general") || feedbackSummary.get("general");
  if (!summary) return 0;

  const averageEase = summary.easeCount ? summary.easeSum / summary.easeCount : null;
  const averageNote = summary.noteCount ? summary.noteSum / summary.noteCount : null;
  const averageLevel = summary.levelCount ? summary.levelSum / summary.levelCount : null;
  const candidateLevel = levelIndex(exercise.level);

  if ((averageEase !== null && averageEase <= 2) || (averageNote !== null && averageNote < 10)) {
    if (averageLevel !== null && candidateLevel !== null && candidateLevel > Math.max(0, averageLevel - 1)) {
      return -0.08;
    }
    return 0.08;
  }

  if ((averageEase !== null && averageEase >= 4.3) && (averageNote === null || averageNote >= 15)) {
    if (averageLevel !== null && candidateLevel !== null && candidateLevel <= averageLevel) {
      return -0.04;
    }
    return 0.06;
  }

  return 0;
}

function selectWithMmr(candidates, target) {
  const remaining = candidates
    .slice()
    .sort((a, b) => baseScore(b) - baseScore(a));
  const selected = [];

  while (selected.length < target && remaining.length) {
    let bestIndex = 0;
    let bestScore = Number.NEGATIVE_INFINITY;

    for (let index = 0; index < remaining.length; index += 1) {
      const candidate = remaining[index];
      candidate.diversity_score = selected.length === 0 ? 1 : diversityAgainstSelected(candidate, selected);
      candidate.final_score =
        SCORE_WEIGHTS.relevance * candidate.relevance_score +
        SCORE_WEIGHTS.authority * candidate.authority_score +
        SCORE_WEIGHTS.diversity * candidate.diversity_score;

      if (candidate.final_score > bestScore) {
        bestScore = candidate.final_score;
        bestIndex = index;
      }
    }

    selected.push(remaining.splice(bestIndex, 1)[0]);
  }

  return selected;
}

function buildProfileWeights(blockers, diagnosticResponses, temperature) {
  const scores = new Map();
  const weights = new Map();

  if (Array.isArray(diagnosticResponses)) {
    for (const response of diagnosticResponses) {
      const type = normalizeKey(response && response.dyslexia_type);
      if (!type) continue;
      const value = clampNumber(response.response_value, 0, 1, 0);
      const weight = clampNumber(response.weight, 0, 10, 1);
      scores.set(type, (scores.get(type) || 0) + value * weight);
      weights.set(type, (weights.get(type) || 0) + weight);
    }
  }

  for (const [type, total] of scores.entries()) {
    const denominator = weights.get(type) || 1;
    scores.set(type, total / denominator);
  }

  if (!scores.size && Array.isArray(blockers)) {
    for (const blocker of blockers) {
      const type = normalizeKey(blocker);
      if (type) scores.set(type, 1);
    }
  }

  if (!scores.size) {
    scores.set("general", 1);
  }

  const raw = Array.from(scores.entries()).map(([type, score]) => [
    type,
    Math.exp(-score / temperature)
  ]);
  const sum = raw.reduce((accumulator, [, value]) => accumulator + value, 0) || 1;

  return new Map(raw.map(([type, value]) => [type, value / sum]));
}

function weightedRelevance(profileSimilarities, profileWeights) {
  let score = 0;

  for (const [profile, weight] of profileWeights.entries()) {
    const similarity = profileSimilarities.get(profile);
    score += weight * clampNumber(similarity, 0, 1, 0.25);
  }

  return clampNumber(score, 0, 1, 0);
}

function inferSimilarities(exercise, profileWeights, embeddingCentroids) {
  const values = new Map();
  const haystack = normalizeKey([exercise.domain, exercise.title, exercise.content].filter(Boolean).join(" "));

  for (const profile of profileWeights.keys()) {
    const centroid = embeddingCentroids.get(profile);
    if (exercise.embedding && centroid) {
      values.set(profile, clampNumber((cosineSimilarity(exercise.embedding, centroid) + 1) / 2, 0, 1, 0.45));
    } else if (profile === "general") {
      values.set(profile, 0.45);
    } else if (haystack.includes(profile)) {
      values.set(profile, 0.68);
    } else {
      values.set(profile, 0.35);
    }
  }

  return values;
}

function buildEmbeddingCentroids(exercises, profileWeights) {
  const centroids = new Map();
  const allEmbeddings = exercises.map((exercise) => exercise.embedding).filter(Boolean);

  for (const profile of profileWeights.keys()) {
    const matched = exercises
      .filter((exercise) => {
        if (!exercise.embedding) return false;
        if (profile === "general") return true;
        const haystack = normalizeKey([exercise.domain, exercise.title, exercise.content].filter(Boolean).join(" "));
        return haystack.includes(profile);
      })
      .map((exercise) => exercise.embedding);
    const vectors = matched.length ? matched : allEmbeddings;
    const centroid = averageVector(vectors);
    if (centroid) centroids.set(profile, centroid);
  }

  return centroids;
}

function averageVector(vectors) {
  if (!Array.isArray(vectors) || !vectors.length) return null;
  const width = vectors[0].length;
  if (!width || vectors.some((vector) => vector.length !== width)) return null;
  const output = new Array(width).fill(0);
  for (const vector of vectors) {
    for (let index = 0; index < width; index += 1) {
      output[index] += vector[index];
    }
  }
  return output.map((value) => value / vectors.length);
}

function diversityAgainstSelected(candidate, selected) {
  let minDistance = 1;

  for (const item of selected) {
    const distance = candidate.embedding && item.embedding
      ? 1 - cosineSimilarity(candidate.embedding, item.embedding)
      : domainDistance(candidate, item);
    minDistance = Math.min(minDistance, clampNumber(distance, 0, 1, 1));
  }

  return minDistance;
}

function domainDistance(a, b) {
  if (!a.domain || !b.domain) return 1;
  return normalizeKey(a.domain) === normalizeKey(b.domain) ? 0.35 : 1;
}

function levelIndex(value) {
  const match = String(value || "").match(/(\d+)/);
  if (!match) return null;
  const number = Number(match[1]);
  if (!Number.isFinite(number)) return null;
  return Math.max(0, number - 1);
}

function cosineSimilarity(a, b) {
  if (!a || !b || a.length !== b.length || !a.length) return 0;
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let index = 0; index < a.length; index += 1) {
    dot += a[index] * b[index];
    normA += a[index] * a[index];
    normB += b[index] * b[index];
  }
  if (!normA || !normB) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

function baseScore(candidate) {
  return SCORE_WEIGHTS.relevance * candidate.relevance_score +
    SCORE_WEIGHTS.authority * candidate.authority_score +
    SCORE_WEIGHTS.diversity;
}

function mapExerciseRow(row) {
  return {
    exercise_id: String(row.exercise_id),
    title: row.title || "",
    content: row.content || "",
    domain: row.domain || null,
    level: row.level === null || row.level === undefined ? null : row.level,
    age_min: row.age_min === null || row.age_min === undefined ? null : Number(row.age_min),
    age_max: row.age_max === null || row.age_max === undefined ? null : Number(row.age_max),
    correct_answer: row.correct_answer || null,
    hint: row.hint || null,
    embedding: parseVector(row.embedding_text)
  };
}

function parseVector(value) {
  if (!value || typeof value !== "string") return null;
  const trimmed = value.trim().replace(/^\[/, "").replace(/\]$/, "");
  if (!trimmed) return null;
  const vector = trimmed.split(",").map((part) => Number(part.trim()));
  return vector.every((number) => Number.isFinite(number)) ? vector : null;
}

function average(values) {
  const finite = values.filter((value) => Number.isFinite(value));
  if (!finite.length) return 0;
  return finite.reduce((sum, value) => sum + value, 0) / finite.length;
}

function clampInteger(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, Math.round(number)));
}

function clampNumber(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, number));
}

function roundScore(value) {
  return Math.round(clampNumber(value, 0, 1, 0) * 1000000) / 1000000;
}

function normalizeKey(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function normalizeTextForMatch(value) {
  return normalizeKey(value)
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function safeIdentifier(value) {
  const identifier = String(value || "").trim();
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(identifier)) {
    throw new Error(`Identifiant SQL invalide: ${identifier}`);
  }
  return identifier;
}

function quoteIdent(identifier) {
  return `"${safeIdentifier(identifier).replace(/"/g, '""')}"`;
}

function isMissingColumn(error) {
  return error && error.code === "42703";
}

function isMissingRelation(error) {
  return error && (error.code === "42P01" || error.code === "3F000");
}

async function runWithHistoryTable(operation, options = {}) {
  for (const historyTable of HISTORY_TABLES) {
    try {
      return await operation(historyTable);
    } catch (error) {
      if (isMissingRelation(error)) continue;
      throw error;
    }
  }

  if (options.allowMissing) {
    console.warn("[rumba-ex-api] historique indisponible, operation ignoree");
    return null;
  }

  const error = new Error("Recommendation history table not found");
  error.code = "42P01";
  throw error;
}

function unique(values) {
  return Array.from(new Set(values));
}

module.exports = {
  getRecommendations,
  insertRecommendationHistory,
  resetRecommendationHistory,
  saveExerciseFeedback
};
