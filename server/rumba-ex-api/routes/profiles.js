const express = require("express");
const {
  directusFetch,
  extractData,
  validateDirectusToken
} = require("../middleware/auth");

const router = express.Router();

router.get("/", validateDirectusToken, async (req, res, next) => {
  try {
    const payload = await directusFetch("/items/rumba_ex_profiles", {
      token: req.directusToken,
      query: {
        fields: "id,student_name,age,blockers,exercise_target,temperature,date_created,date_updated",
        sort: "-date_created",
        "filter[user_created][_eq]": req.userId
      }
    });

    return res.json(extractData(payload) || []);
  } catch (error) {
    return next(error);
  }
});

router.post("/", validateDirectusToken, async (req, res, next) => {
  try {
    const profile = validateProfilePayload(req.body || {});
    const payload = await directusFetch("/items/rumba_ex_profiles", {
      method: "POST",
      token: req.directusToken,
      body: profile
    });

    return res.status(201).json(extractData(payload));
  } catch (error) {
    if (error.status === 400) {
      return res.status(400).json({ error: error.publicMessage || "Profil invalide." });
    }
    return next(error);
  }
});

router.delete("/:id", validateDirectusToken, async (req, res, next) => {
  try {
    const profileId = String(req.params.id || "");
    if (!isUuid(profileId)) {
      return res.status(400).json({ error: "Identifiant de profil invalide." });
    }

    await assertProfileOwnership(profileId, req.directusToken, req.userId);
    await directusFetch(`/items/rumba_ex_profiles/${encodeURIComponent(profileId)}`, {
      method: "DELETE",
      token: req.directusToken
    });

    return res.json({ ok: true });
  } catch (error) {
    if (error.status === 403 || error.status === 404) {
      return res.status(403).json({ error: "Acces interdit a ce profil." });
    }
    return next(error);
  }
});

async function assertProfileOwnership(profileId, token, userId) {
  const payload = await directusFetch(`/items/rumba_ex_profiles/${encodeURIComponent(profileId)}`, {
    token,
    query: {
      fields: "id,user_created"
    }
  });
  const profile = extractData(payload);
  const owner = profile?.user_created && typeof profile.user_created === "object" ? profile.user_created.id : profile?.user_created;

  if (!profile || profile.id !== profileId || (!owner || owner !== userId)) {
    const error = new Error("Forbidden profile");
    error.status = 403;
    throw error;
  }

  return profile;
}

function validateProfilePayload(payload) {
  const studentName = String(payload.student_name || "").trim();
  const age = Number(payload.age);
  const blockers = Array.isArray(payload.blockers)
    ? payload.blockers.map((item) => String(item).trim()).filter(Boolean)
    : [];
  const exerciseTarget = payload.exercise_target === undefined ? 3 : Number(payload.exercise_target);
  const temperature = payload.temperature === undefined ? 0.8 : Number(payload.temperature);

  if (!studentName || studentName.length > 100) {
    throwBadRequest("Le prenom de l'eleve est requis.");
  }
  if (!Number.isInteger(age) || age < 6 || age > 14) {
    throwBadRequest("L'age doit etre compris entre 6 et 14 ans.");
  }
  if (!blockers.length) {
    throwBadRequest("Au moins un point de blocage est requis.");
  }
  if (!Number.isInteger(exerciseTarget) || exerciseTarget < 1 || exerciseTarget > 5) {
    throwBadRequest("Le nombre d'exercices doit etre compris entre 1 et 5.");
  }
  if (!Number.isFinite(temperature) || temperature < 0.1 || temperature > 3) {
    throwBadRequest("La temperature doit etre comprise entre 0.1 et 3.");
  }

  return {
    student_name: studentName,
    age,
    blockers,
    exercise_target: exerciseTarget,
    temperature
  };
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
module.exports.assertProfileOwnership = assertProfileOwnership;
