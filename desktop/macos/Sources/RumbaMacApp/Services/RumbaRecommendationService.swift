import Foundation

@MainActor
final class RumbaRecommendationService {
    private let profileRepository: ProfileRepository
    private let exerciseRepository: ExerciseRepository

    // F_e = alpha * R_e + beta * A_e + gamma * D_e
    private let alphaRelevance = 0.68
    private let betaAuthority = 0.22
    private let gammaDiversity = 0.10

    init(profileRepository: ProfileRepository, exerciseRepository: ExerciseRepository) {
        self.profileRepository = profileRepository
        self.exerciseRepository = exerciseRepository
    }

    func recommendGuaranteed(profile: StudentProfile, responses: [DiagnosticResponse]) async -> [RankedExercise] {
        let history = (try? await profileRepository.fetchHistoryExerciseIDs(profileID: profile.id)) ?? []

        do {
            let ranked = try await recommend(profile: profile, responses: responses)
            if !ranked.isEmpty {
                return ranked
            }
        } catch {
            // Fallback handled below.
        }

        do {
            let fallback = try await exerciseRepository.fetchAnyEligibleExercises(
                age: profile.age,
                excludingIDs: history,
                limit: profile.targetExerciseCount
            )

            return fallback.enumerated().map { index, exercise in
                let score = Double(max(1, profile.targetExerciseCount - index)) / Double(max(1, profile.targetExerciseCount))
                return RankedExercise(
                    id: exercise.id,
                    exercise: exercise,
                    relevance: score,
                    authority: score,
                    diversity: 1.0,
                    finalScore: score
                )
            }
        } catch {
            return []
        }
    }

    func recommend(profile: StudentProfile, responses: [DiagnosticResponse]) async throws -> [RankedExercise] {
        let history = try await profileRepository.fetchHistoryExerciseIDs(profileID: profile.id)

        // 1) S_p: weighted diagnostic error score by dyslexia profile.
        var errorScores: [DyslexiaType: Double] = [:]
        for type in profile.selectedBlockers {
            errorScores[type] = 0
        }

        for response in responses where profile.selectedBlockers.contains(response.item.dyslexiaType) {
            errorScores[response.item.dyslexiaType, default: 0] += response.value * response.item.weight
        }

        // 2) c_p: inverse softmax confidence with configurable temperature.
        let confidences = RecommendationMath.softmaxInverse(scores: errorScores, temperature: profile.temperature)

        // 3) M_p,e from precomputed table, with pgvector fallback.
        var matrixByExercise: [UUID: [DyslexiaType: Double]] = [:]
        let signalThreshold = max(profile.targetExerciseCount * 8, 24)

        for blocker in profile.selectedBlockers {
            var similarities = try await exerciseRepository.fetchPrecomputedSimilarities(type: blocker, age: profile.age)

            // If precomputed signal is weak, reinforce with nearest-embedding similarities.
            if similarities.count < signalThreshold {
                let dynamic = try await exerciseRepository.fetchDynamicSimilarities(type: blocker, age: profile.age)
                if similarities.isEmpty {
                    similarities = dynamic
                } else {
                    for (exerciseID, score) in dynamic {
                        let current = similarities[exerciseID] ?? -Double.greatestFiniteMagnitude
                        similarities[exerciseID] = max(current, score)
                    }
                }
            }

            for (exerciseID, cosine) in similarities where !history.contains(exerciseID) {
                var existing = matrixByExercise[exerciseID] ?? [:]
                existing[blocker] = cosine
                matrixByExercise[exerciseID] = existing
            }
        }

        if matrixByExercise.isEmpty {
            // Hard fallback: direct embedding nearest-neighbor by selected profiles.
            for blocker in profile.selectedBlockers {
                let dynamic = try await exerciseRepository.fetchDynamicSimilarities(type: blocker, age: profile.age)
                for (exerciseID, cosine) in dynamic where !history.contains(exerciseID) {
                    var existing = matrixByExercise[exerciseID] ?? [:]
                    existing[blocker] = cosine
                    matrixByExercise[exerciseID] = existing
                }
            }
        }

        guard !matrixByExercise.isEmpty else {
            let fallback = try await exerciseRepository.fetchAnyEligibleExercises(
                age: profile.age,
                excludingIDs: history,
                limit: profile.targetExerciseCount
            )

            return fallback.enumerated().map { index, exercise in
                let score = Double(max(1, profile.targetExerciseCount - index)) / Double(max(1, profile.targetExerciseCount))
                return RankedExercise(
                    id: exercise.id,
                    exercise: exercise,
                    relevance: score,
                    authority: score,
                    diversity: 1.0,
                    finalScore: score
                )
            }
        }

        // 4) R_e = sum_p (c_p * M_p,e)
        var relevanceByExercise: [UUID: Double] = [:]
        var authorityRawByExercise: [UUID: Double] = [:]

        for (exerciseID, byProfile) in matrixByExercise {
            var relevance = 0.0
            for (profileType, confidence) in confidences {
                relevance += confidence * (byProfile[profileType] ?? 0)
            }
            relevanceByExercise[exerciseID] = relevance

            let sims = byProfile.map { pair in pair.value }
            authorityRawByExercise[exerciseID] = sims.isEmpty ? 0 : (sims.reduce(0, +) / Double(sims.count))
        }

        let exercises = try await exerciseRepository.fetchExercises(ids: Array(matrixByExercise.keys))
        guard !exercises.isEmpty else {
            let fallback = try await exerciseRepository.fetchAnyEligibleExercises(
                age: profile.age,
                excludingIDs: history,
                limit: profile.targetExerciseCount
            )

            return fallback.enumerated().map { index, exercise in
                let score = Double(max(1, profile.targetExerciseCount - index)) / Double(max(1, profile.targetExerciseCount))
                return RankedExercise(
                    id: exercise.id,
                    exercise: exercise,
                    relevance: score,
                    authority: score,
                    diversity: 1.0,
                    finalScore: score
                )
            }
        }

        let authorityValues = authorityRawByExercise.values
        let minAuthority = authorityValues.min() ?? 0
        let maxAuthority = authorityValues.max() ?? 1

        var authorityByExercise: [UUID: Double] = [:]
        for (exerciseID, authorityRaw) in authorityRawByExercise {
            authorityByExercise[exerciseID] = RecommendationMath.normalize(authorityRaw, min: minAuthority, max: maxAuthority)
        }

        // 5) Diversity + authority reranking to produce F_e.
        var remainingIDs = Set(exercises.keys)
        var selected: [RankedExercise] = []
        var usedDomains: [ExerciseDomain: Int] = [:]
        var usedLevels: [ExerciseLevel: Int] = [:]

        while selected.count < profile.targetExerciseCount && !remainingIDs.isEmpty {
            var best: RankedExercise?

            for exerciseID in remainingIDs {
                guard let exercise = exercises[exerciseID] else { continue }

                let relevance = relevanceByExercise[exerciseID] ?? 0
                let authority = authorityByExercise[exerciseID] ?? 0
                let diversity = diversityScore(
                    for: exercise,
                    usedDomains: usedDomains,
                    usedLevels: usedLevels
                )

                let finalScore = (alphaRelevance * relevance) +
                                 (betaAuthority * authority) +
                                 (gammaDiversity * diversity)

                let ranked = RankedExercise(
                    id: exerciseID,
                    exercise: exercise,
                    relevance: relevance,
                    authority: authority,
                    diversity: diversity,
                    finalScore: finalScore
                )

                if let currentBest = best {
                    if ranked.finalScore > currentBest.finalScore {
                        best = ranked
                    }
                } else {
                    best = ranked
                }
            }

            guard let chosen = best else { break }
            selected.append(chosen)
            remainingIDs.remove(chosen.exercise.id)
            usedDomains[chosen.exercise.domain, default: 0] += 1
            usedLevels[chosen.exercise.level, default: 0] += 1
        }

        return selected
    }

    private func diversityScore(
        for exercise: Exercise,
        usedDomains: [ExerciseDomain: Int],
        usedLevels: [ExerciseLevel: Int]
    ) -> Double {
        let domainCount = usedDomains[exercise.domain] ?? 0
        let levelCount = usedLevels[exercise.level] ?? 0

        // Favor unseen domains and levels in the current recommendation batch.
        let domainComponent = max(0.0, 1.0 - (Double(domainCount) * 0.45))
        let levelComponent = max(0.0, 1.0 - (Double(levelCount) * 0.25))
        return RecommendationMath.bounded((0.7 * domainComponent) + (0.3 * levelComponent))
    }
}
