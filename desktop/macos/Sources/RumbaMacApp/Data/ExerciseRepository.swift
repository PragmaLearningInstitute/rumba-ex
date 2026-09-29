import Foundation
import PostgresNIO

@MainActor
struct ExerciseRepository {
    private let db: PostgresService
    private let localStore: LocalBackendStore
    private let allowLocalFallback: Bool

    init(
        db: PostgresService,
        localStore: LocalBackendStore = .shared,
        allowLocalFallback: Bool = false
    ) {
        self.db = db
        self.localStore = localStore
        self.allowLocalFallback = allowLocalFallback
    }

    func fetchPrecomputedSimilarities(type: DyslexiaType, age: Int) async throws -> [UUID: Double] {
        do {
            let rows = try await db.client.query(
                """
                SELECT pes.exercise_id,
                       pes.cosine_sim
                FROM profile_exercise_similarity pes
                INNER JOIN exercise e ON e.exercise_id = pes.exercise_id
                WHERE pes.dyslexia_type = \(type.rawValue)
                  AND e.age_min <= \(age)
                  AND e.age_max >= \(age);
                """
            )

            var similarities: [UUID: Double] = [:]
            for try await tuple in rows.decode((UUID, Double).self) {
                similarities[tuple.0] = tuple.1
            }
            return similarities
        } catch {
            if allowLocalFallback {
                return await localStore.fetchPrecomputedSimilarities(type: type, age: age)
            }
            throw error
        }
    }

    func fetchDynamicSimilarities(type: DyslexiaType, age: Int) async throws -> [UUID: Double] {
        do {
            let rows = try await db.client.query(
                """
                SELECT e.exercise_id,
                       (1 - (lp.profil_learner_embedding <=> e.embedding))::double precision AS cosine_sim
                FROM learnerprofile lp
                CROSS JOIN exercise e
                WHERE lp.dyslexia_type = \(type.rawValue)
                  AND e.embedding IS NOT NULL
                  AND lp.profil_learner_embedding IS NOT NULL
                  AND e.age_min <= \(age)
                  AND e.age_max >= \(age);
                """
            )

            var similarities: [UUID: Double] = [:]
            for try await tuple in rows.decode((UUID, Double).self) {
                similarities[tuple.0] = tuple.1
            }
            return similarities
        } catch {
            if allowLocalFallback {
                return await localStore.fetchDynamicSimilarities(type: type, age: age)
            }
            throw error
        }
    }

    func fetchExercises(ids: [UUID]) async throws -> [UUID: Exercise] {
        guard !ids.isEmpty else { return [:] }

        do {
            let rows = try await db.client.query(
                """
                SELECT exercise_id,
                       title,
                       content,
                       domain::text,
                       level::text,
                       age_min,
                       age_max,
                       correct_answer,
                       COALESCE(hint, '')
                FROM exercise
                WHERE exercise_id = ANY(\(ids));
                """
            )

            var exercises: [UUID: Exercise] = [:]

            for try await tuple in rows.decode((UUID, String, String, String, String, Int, Int, String, String).self) {
                guard let domain = ExerciseDomain(rawValue: tuple.3),
                      let level = ExerciseLevel(rawValue: tuple.4) else {
                    continue
                }

                let exercise = Exercise(
                    id: tuple.0,
                    title: tuple.1,
                    content: tuple.2,
                    domain: domain,
                    level: level,
                    ageMin: tuple.5,
                    ageMax: tuple.6,
                    correctAnswer: tuple.7,
                    hint: tuple.8.isEmpty ? nil : tuple.8
                )
                exercises[exercise.id] = exercise
            }

            if exercises.isEmpty {
                // Driver-level UUID[] binding can fail silently on some setups.
                // Retry with an explicit IN (...) clause built from trusted UUIDs.
                let uuidList = ids
                    .map { "'\($0.uuidString)'::uuid" }
                    .joined(separator: ", ")

                let fallbackRows = try await db.client.query(
                    """
                    SELECT exercise_id,
                           title,
                           content,
                           domain::text,
                           level::text,
                           age_min,
                           age_max,
                           correct_answer,
                           COALESCE(hint, '')
                    FROM exercise
                    WHERE exercise_id IN (\(uuidList));
                    """
                )

                for try await tuple in fallbackRows.decode((UUID, String, String, String, String, Int, Int, String, String).self) {
                    guard let domain = ExerciseDomain(rawValue: tuple.3),
                          let level = ExerciseLevel(rawValue: tuple.4) else {
                        continue
                    }

                    let exercise = Exercise(
                        id: tuple.0,
                        title: tuple.1,
                        content: tuple.2,
                        domain: domain,
                        level: level,
                        ageMin: tuple.5,
                        ageMax: tuple.6,
                        correctAnswer: tuple.7,
                        hint: tuple.8.isEmpty ? nil : tuple.8
                    )
                    exercises[exercise.id] = exercise
                }
            }

            if exercises.isEmpty && allowLocalFallback {
                return await localStore.fetchExercises(ids: ids)
            }

            return exercises
        } catch {
            if allowLocalFallback {
                return await localStore.fetchExercises(ids: ids)
            }
            throw error
        }
    }

    func fetchAnyEligibleExercises(age: Int, excludingIDs: Set<UUID>, limit: Int) async throws -> [Exercise] {
        let safeLimit = max(1, limit)

        do {
            let rows = try await db.client.query(
                """
                SELECT exercise_id,
                       title,
                       content,
                       domain::text,
                       level::text,
                       age_min,
                       age_max,
                       correct_answer,
                       COALESCE(hint, '')
                FROM exercise
                WHERE age_min <= \(age)
                  AND age_max >= \(age)
                ORDER BY updated_at DESC NULLS LAST, created_at DESC
                LIMIT \(safeLimit * 10);
                """
            )

            var output: [Exercise] = []

            for try await tuple in rows.decode((UUID, String, String, String, String, Int, Int, String, String).self) {
                guard let domain = ExerciseDomain(rawValue: tuple.3),
                      let level = ExerciseLevel(rawValue: tuple.4) else {
                    continue
                }

                if excludingIDs.contains(tuple.0) {
                    continue
                }

                output.append(
                    Exercise(
                        id: tuple.0,
                        title: tuple.1,
                        content: tuple.2,
                        domain: domain,
                        level: level,
                        ageMin: tuple.5,
                        ageMax: tuple.6,
                        correctAnswer: tuple.7,
                        hint: tuple.8.isEmpty ? nil : tuple.8
                    )
                )

                if output.count >= safeLimit {
                    break
                }
            }

            if !output.isEmpty {
                return output
            }
        } catch {
            if !allowLocalFallback {
                throw error
            }
        }

        guard allowLocalFallback else { return [] }

        let ids = Array(
            await localStore.fetchPrecomputedSimilarities(type: .phonologique, age: age)
                .keys
                .filter { !excludingIDs.contains($0) }
                .prefix(safeLimit)
        )
        let local = await localStore.fetchExercises(ids: ids)
        return ids.compactMap { local[$0] }
    }
}
