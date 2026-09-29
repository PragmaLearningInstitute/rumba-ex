const express = require("express");
const { getBearerToken, validateTokenString } = require("../middleware/auth");
const { recommendRateLimiter } = require("../middleware/rateLimit");
const { assertProfileOwnership } = require("./profiles");
const {
  getRecommendations,
  insertRecommendationHistory,
  resetRecommendationHistory,
  saveExerciseFeedback
} = require("../db/recommend");

const router = express.Router();

router.post("/", recommendRateLimiter, async (req, res, next) => {
  try {
    const token = getBearerToken(req);
    const isGuest = token === "guest";
    let user = null;

    if (!isGuest) {
      user = await validateTokenString(token);
    }

    const payload = validateRecommendationPayload(req.body || {});

    if (payload.profile_id) {
      if (isGuest) {
        return res.status(401).json({ error: "Un profil sauvegarde necessite une session Directus." });
      }
      await assertProfileOwnership(payload.profile_id, token, user.id);
    }

    const recommendations = await getRecommendations(payload);

    if (payload.profile_id && recommendations.length) {
      await insertRecommendationHistory(payload.profile_id, recommendations);
    }

    return res.json(recommendations);
  } catch (error) {
    if (error.status === 400) {
      return res.status(400).json({ error: error.publicMessage || "Demande de recommandation invalide." });
    }
    if (error.status === 401 || error.status === 403 || error.status === 404) {
      return res.status(error.status === 404 ? 403 : error.status).json({ error: "Acces refuse." });
    }
    return next(error);
  }
});

router.post("/history/reset", async (req, res, next) => {
  try {
    const token = getBearerToken(req);
    const user = await validateTokenString(token);
    const profileId = String((req.body && req.body.profile_id) || "");

    if (!isUuid(profileId)) {
      return res.status(400).json({ error: "Identifiant de profil invalide." });
    }

    await assertProfileOwnership(profileId, token, user.id);
    await resetRecommendationHistory(profileId);
    return res.json({ ok: true });
  } catch (error) {
    if (error.status === 401 || error.status === 403 || error.status === 404) {
      return res.status(error.status === 404 ? 403 : error.status).json({ error: "Acces refuse." });
    }
    return next(error);
  }
});

router.post("/feedback", async (req, res, next) => {
  try {
    const token = getBearerToken(req);
    const user = await validateTokenString(token);
    const payload = validateFeedbackPayload(req.body || {});

    await assertProfileOwnership(payload.profile_id, token, user.id);

    if (!isUuid(payload.exercise_id)) {
      return res.status(202).json({ ok: true, stored: false, reason: "local_exercise" });
    }

    const stored = await saveExerciseFeedback(payload.profile_id, payload.exercise_id, {
      note: payload.note,
      ease: payload.ease
    });

    return res.status(stored ? 200 : 202).json({ ok: true, stored });
  } catch (error) {
    if (error.status === 400) {
      return res.status(400).json({ error: error.publicMessage || "Retour exercice invalide." });
    }
    if (error.status === 401 || error.status === 403 || error.status === 404) {
      return res.status(error.status === 404 ? 403 : error.status).json({ error: "Acces refuse." });
    }
    return next(error);
  }
});

function validateRecommendationPayload(payload) {
  const profileId = payload.profile_id ? String(payload.profile_id) : null;
  const age = Number(payload.age);
  const blockers = Array.isArray(payload.blockers)
    ? payload.blockers.map((item) => String(item).trim()).filter(Boolean)
    : [];
  const exerciseTarget = payload.exercise_target === undefined ? 3 : Number(payload.exercise_target);
  const temperature = payload.temperature === undefined ? 0.8 : Number(payload.temperature);
  const diagnosticResponses = Array.isArray(payload.diagnostic_responses)
    ? payload.diagnostic_responses.map(normalizeDiagnosticResponse).filter(Boolean)
    : [];
  const exerciseFeedback = Array.isArray(payload.exercise_feedback)
    ? payload.exercise_feedback.map(normalizeExerciseFeedback).filter(Boolean).slice(0, 100)
    : [];
  const excludeExerciseIds = Array.isArray(payload.exclude_exercise_ids)
    ? payload.exclude_exercise_ids.map((item) => String(item || "").trim()).filter(Boolean).slice(0, 120)
    : [];

  if (profileId && !isUuid(profileId)) {
    throwBadRequest("Identifiant de profil invalide.");
  }
  if (!Number.isInteger(age) || age < 6 || age > 14) {
    throwBadRequest("L'age doit etre compris entre 6 et 14 ans.");
  }
  if (!blockers.length && !diagnosticResponses.length) {
    throwBadRequest("Au moins un point de blocage ou une reponse diagnostique est requis.");
  }
  if (!Number.isInteger(exerciseTarget) || exerciseTarget < 1 || exerciseTarget > 5) {
    throwBadRequest("Le nombre d'exercices doit etre compris entre 1 et 5.");
  }
  if (!Number.isFinite(temperature) || temperature < 0.1 || temperature > 3) {
    throwBadRequest("La temperature doit etre comprise entre 0.1 et 3.");
  }

  return {
    profile_id: profileId,
    age,
    blockers,
    exercise_target: exerciseTarget,
    temperature,
    diagnostic_responses: diagnosticResponses,
    exercise_feedback: exerciseFeedback,
    exclude_exercise_ids: excludeExerciseIds
  };
}

function validateFeedbackPayload(payload) {
  const profileId = String((payload && payload.profile_id) || "");
  const exerciseId = String((payload && payload.exercise_id) || "");
  const note = normalizeNullableNumber(payload && payload.note, 0, 20, "La note doit etre comprise entre 0 et 20.");
  const ease = normalizeNullableInteger(payload && payload.ease, 1, 5, "La facilite doit etre comprise entre 1 et 5.");

  if (!isUuid(profileId)) {
    throwBadRequest("Identifiant de profil invalide.");
  }
  if (!exerciseId) {
    throwBadRequest("Identifiant d'exercice invalide.");
  }
  if (note === null && ease === null) {
    throwBadRequest("Indiquez une note ou une facilite.");
  }

  return {
    profile_id: profileId,
    exercise_id: exerciseId,
    note,
    ease
  };
}

function normalizeDiagnosticResponse(response) {
  if (!response || typeof response !== "object") return null;
  const dyslexiaType = String(response.dyslexia_type || "").trim();
  if (!dyslexiaType) return null;

  return {
    dyslexia_type: dyslexiaType,
    response_value: clampNumber(response.response_value, 0, 1, 0),
    weight: clampNumber(response.weight, 0, 10, 1)
  };
}

function normalizeExerciseFeedback(feedback) {
  if (!feedback || typeof feedback !== "object") return null;
  const exerciseId = String(feedback.exercise_id || "").trim();
  const domain = String(feedback.domain || "").trim();
  const note = normalizeNullableNumber(feedback.note, 0, 20, "");
  const ease = normalizeNullableInteger(feedback.ease, 1, 5, "");
  if (!exerciseId && !domain) return null;

  return {
    exercise_id: exerciseId || null,
    domain: domain || null,
    level: feedback.level === undefined || feedback.level === null ? null : String(feedback.level),
    note,
    ease,
    updated_at: feedback.updated_at ? String(feedback.updated_at) : null
  };
}

function normalizeNullableNumber(value, min, max, message) {
  if (value === undefined || value === null || value === "") return null;
  const number = Number(value);
  if (!Number.isFinite(number) || number < min || number > max) {
    if (message) throwBadRequest(message);
    return null;
  }
  return number;
}

function normalizeNullableInteger(value, min, max, message) {
  if (value === undefined || value === null || value === "") return null;
  const number = Number(value);
  if (!Number.isInteger(number) || number < min || number > max) {
    if (message) throwBadRequest(message);
    return null;
  }
  return number;
}

function clampNumber(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(min, Math.min(max, number));
}

function throwBadRequest(message) {
  const error = new Error(message);
  error.status = 400;
  error.publicMessage = message;
  throw error;
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

module.exports = router;
