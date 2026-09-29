import Foundation
import PostgresNIO

@MainActor
struct ProfileRepository {
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

    func loadProfile(named name: String) async throws -> StudentProfile? {
        do {
            let rows = try await db.client.query(
                """
                SELECT id,
                       student_name,
                       age,
                       array_to_string(blockers, ',') AS blockers_csv,
                       exercise_target,
                       temperature
                FROM student_profile
                WHERE student_name = \(name)
                LIMIT 1;
                """
            )

            for try await tuple in rows.decode((UUID, String, Int, String, Int, Double).self) {
                return StudentProfile(
                    id: tuple.0,
                    studentName: tuple.1,
                    age: tuple.2,
                    selectedBlockers: parseBlockersCSV(tuple.3),
                    targetExerciseCount: tuple.4,
                    temperature: tuple.5
                )
            }
            return nil
        } catch {
            if allowLocalFallback {
                return await localStore.loadProfile(named: name)
            }
            throw error
        }
    }

    func createProfile(named name: String, age: Int = 9) async throws -> StudentProfile {
        do {
            let defaultBlockers: [String] = [DyslexiaType.phonologique.rawValue]
            let blockersCSV = defaultBlockers.joined(separator: ",")
            let rows = try await db.client.query(
                """
                INSERT INTO student_profile (student_name, age, blockers, exercise_target, temperature)
                VALUES (
                    \(name),
                    \(age),
                    string_to_array(\(blockersCSV), ',')::dyslexia_type_enum[],
                    3,
                    0.8
                )
                RETURNING id,
                          student_name,
                          age,
                          array_to_string(blockers, ',') AS blockers_csv,
                          exercise_target,
                          temperature;
                """
            )

            for try await tuple in rows.decode((UUID, String, Int, String, Int, Double).self) {
                return StudentProfile(
                    id: tuple.0,
                    studentName: tuple.1,
                    age: tuple.2,
                    selectedBlockers: parseBlockersCSV(tuple.3),
                    targetExerciseCount: tuple.4,
                    temperature: tuple.5
                )
            }
            throw RepositoryError.emptyResult("Impossible de creer le profil")
        } catch {
            if allowLocalFallback {
                return try await localStore.createProfile(named: name, age: age)
            }
            throw error
        }
    }

    func upsertProfile(name: String, age: Int, blockers: [DyslexiaType], targetCount: Int, temperature: Double) async throws -> StudentProfile {
        do {
            let blockersRaw = blockers.map { type in type.rawValue }
            let blockersCSV = blockersRaw.joined(separator: ",")
            let rows = try await db.client.query(
                """
                INSERT INTO student_profile (student_name, age, blockers, exercise_target, temperature)
                VALUES (
                    \(name),
                    \(age),
                    string_to_array(\(blockersCSV), ',')::dyslexia_type_enum[],
                    \(targetCount),
                    \(temperature)
                )
                ON CONFLICT (student_name)
                DO UPDATE SET age = EXCLUDED.age,
                              blockers = EXCLUDED.blockers,
                              exercise_target = EXCLUDED.exercise_target,
                              temperature = EXCLUDED.temperature,
                              updated_at = NOW()
                RETURNING id,
                          student_name,
                          age,
                          array_to_string(blockers, ',') AS blockers_csv,
                          exercise_target,
                          temperature;
                """
            )

            for try await tuple in rows.decode((UUID, String, Int, String, Int, Double).self) {
                return StudentProfile(
                    id: tuple.0,
                    studentName: tuple.1,
                    age: tuple.2,
                    selectedBlockers: parseBlockersCSV(tuple.3),
                    targetExerciseCount: tuple.4,
                    temperature: tuple.5
                )
            }
            throw RepositoryError.emptyResult("Impossible de sauvegarder le profil")
        } catch {
            if allowLocalFallback {
                return try await localStore.upsertProfile(
                    name: name,
                    age: age,
                    blockers: blockers,
                    targetCount: targetCount,
                    temperature: temperature
                )
            }
            throw error
        }
    }

    func saveDiagnosticResponses(profileID: UUID, responses: [DiagnosticResponse]) async throws {
        do {
            _ = try await db.client.query(
                "DELETE FROM diagnostic_response WHERE profile_id = \(profileID);"
            )

            for response in responses {
                _ = try await db.client.query(
                    """
                    INSERT INTO diagnostic_response (
                        profile_id,
                        dyslexia_type,
                        item_prompt,
                        response_value,
                        weight
                    )
                    VALUES (
                        \(profileID),
                        CAST(\(response.item.dyslexiaType.rawValue) AS dyslexia_type_enum),
                        \(response.item.prompt),
                        \(response.value),
                        \(response.item.weight)
                    );
                    """
                )
            }
        } catch {
            if allowLocalFallback {
                try await localStore.saveDiagnosticResponses(profileID: profileID, responses: responses)
                return
            }
            throw error
        }
    }

    func fetchHistoryExerciseIDs(profileID: UUID) async throws -> Set<UUID> {
        do {
            let rows = try await db.client.query(
                """
                SELECT exercise_id
                FROM profile_recommendation_history
                WHERE profile_id = \(profileID);
                """
            )

            var output = Set<UUID>()
            for try await tuple in rows.decode((UUID).self) {
                output.insert(tuple)
            }
            return output
        } catch {
            if allowLocalFallback {
                return await localStore.fetchHistoryExerciseIDs(profileID: profileID)
            }
            throw error
        }
    }

    func saveRecommendationHistory(profileID: UUID, ranked: [RankedExercise]) async throws {
        do {
            for recommendation in ranked {
                _ = try await db.client.query(
                    """
                    INSERT INTO profile_recommendation_history (
                        profile_id,
                        exercise_id,
                        final_score,
                        relevance_score,
                        authority_score,
                        diversity_score
                    )
                    SELECT
                        \(profileID),
                        e.exercise_id,
                        \(recommendation.finalScore),
                        \(recommendation.relevance),
                        \(recommendation.authority),
                        \(recommendation.diversity)
                    FROM exercise e
                    WHERE e.exercise_id = \(recommendation.exercise.id)
                    ON CONFLICT (profile_id, exercise_id) DO NOTHING;
                    """
                )
            }
        } catch {
            if allowLocalFallback {
                try await localStore.saveRecommendationHistory(profileID: profileID, ranked: ranked)
                return
            }
            throw error
        }
    }

    func listProfileNames() async throws -> [String] {
        do {
            let rows = try await db.client.query(
                """
                SELECT student_name
                FROM student_profile
                ORDER BY student_name;
                """
            )

            var names: [String] = []
            for try await tuple in rows.decode((String).self) {
                names.append(tuple)
            }
            return names
        } catch {
            if allowLocalFallback {
                return await localStore.listProfileNames()
            }
            throw error
        }
    }

    private func parseBlockersCSV(_ csv: String) -> [DyslexiaType] {
        csv.split(separator: ",").compactMap { raw in
            DyslexiaType(rawValue: String(raw))
        }
    }
}

enum RepositoryError: Error, LocalizedError {
    case emptyResult(String)

    var errorDescription: String? {
        switch self {
        case .emptyResult(let message):
            return message
        }
    }
}
