import AppKit
import Foundation
import PostgresNIO
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var studentNameInput: String = ""
    @Published var knownProfiles: [String] = []

    @Published var currentProfile: StudentProfile?

    @Published var selectedAge: Int = 9 {
        didSet {
            let clamped = min(14, max(6, selectedAge))
            if clamped != selectedAge {
                selectedAge = clamped
            }
        }
    }
    @Published var selectedBlockers: Set<DyslexiaType> = [.phonologique] {
        didSet { regenerateDiagnosticResponses() }
    }
    @Published var targetExerciseCount: Int = 3 {
        didSet {
            let clamped = min(5, max(1, targetExerciseCount))
            if clamped != targetExerciseCount {
                targetExerciseCount = clamped
            }
        }
    }
    @Published var temperature: Double = 0.8 {
        didSet {
            let clamped = min(3.0, max(0.1, temperature))
            if clamped != temperature {
                temperature = clamped
            }
        }
    }

    @Published var diagnosticResponses: [DiagnosticResponse] = []
    @Published var recommendations: [RankedExercise] = []

    @Published var exportOptions = ExportOptions()

    @Published var isBusy = false
    @Published var infoMessage: String = ""
    @Published var errorMessage: String = ""
    @Published var backendStatusText: String = ""

    private let dbService: PostgresService
    private let profileRepository: ProfileRepository
    private let recommendationService: RumbaRecommendationService
    private let docxExporter = DocxExporter()
    private let allowLocalFallback: Bool

    init() {
        let config = AppConfiguration.loadFromEnvironment()
        let dbService = PostgresService(configuration: config)
        let profileRepository = ProfileRepository(
            db: dbService,
            allowLocalFallback: config.enableLocalFallback
        )
        let exerciseRepository = ExerciseRepository(
            db: dbService,
            allowLocalFallback: config.enableLocalFallback
        )

        self.dbService = dbService
        self.profileRepository = profileRepository
        self.recommendationService = RumbaRecommendationService(
            profileRepository: profileRepository,
            exerciseRepository: exerciseRepository
        )
        self.allowLocalFallback = config.enableLocalFallback
        self.backendStatusText = "Base SQL cible: \(config.dbName)"

        regenerateDiagnosticResponses()

        Task {
            let sqlAvailable = await dbService.ping()
            if sqlAvailable {
                backendStatusText = "Base SQL active: \(config.dbHost):\(config.dbPort)/\(config.dbName)"
            } else if allowLocalFallback {
                backendStatusText = "Mode local actif: SQL indisponible, fallback local utilise."
            } else {
                backendStatusText = "SQL indisponible: connexion requise vers \(config.dbHost):\(config.dbPort)/\(config.dbName)"
                errorMessage = "Connexion SQL impossible. Verifie la base et les variables RUMBA_DB_*."
            }
            await refreshProfileNames()
        }
    }

    var isLoggedIn: Bool {
        currentProfile != nil
    }

    var trimmedStudentName: String {
        studentNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasStudentNameInput: Bool {
        !trimmedStudentName.isEmpty
    }

    var typedProfileExists: Bool {
        guard hasStudentNameInput else { return false }
        return knownProfiles.contains(where: { name in
            name.compare(trimmedStudentName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
    }

    func refreshProfileNames() async {
        do {
            knownProfiles = try await withRetry {
                try await profileRepository.listProfileNames()
            }
        } catch {
            // Keep the previous list on transient SQL failures.
        }
    }

    func loginExistingProfile() async {
        guard hasStudentNameInput else {
            errorMessage = "Entre un nom d'eleve pour continuer."
            return
        }

        isBusy = true
        errorMessage = ""
        infoMessage = ""
        defer { isBusy = false }

        do {
            if let loaded = try await withRetry(operation: {
                try await profileRepository.loadProfile(named: trimmedStudentName)
            }) {
                apply(profile: loaded)
                infoMessage = "Profil charge: \(loaded.studentName)"
            } else {
                errorMessage = "Profil introuvable. Clique sur \"Creer le profil\"."
            }
            await refreshProfileNames()
        } catch {
            errorMessage = "Erreur de connexion profil: \(describe(error))"
        }
    }

    func createProfileFromInput() async {
        guard hasStudentNameInput else {
            errorMessage = "Entre un nom d'eleve pour continuer."
            return
        }

        isBusy = true
        errorMessage = ""
        infoMessage = ""
        defer { isBusy = false }

        do {
            let blockers = Array(selectedBlockers).sorted(by: { lhs, rhs in lhs.rawValue < rhs.rawValue })
            let created = try await withRetry {
                try await profileRepository.upsertProfile(
                    name: trimmedStudentName,
                    age: selectedAge,
                    blockers: blockers,
                    targetCount: targetExerciseCount,
                    temperature: temperature
                )
            }
            apply(profile: created)
            infoMessage = typedProfileExists
                ? "Profil existant charge: \(created.studentName)"
                : "Nouveau profil cree: \(created.studentName)"
            await refreshProfileNames()
        } catch {
            errorMessage = "Echec de creation profil: \(describe(error))"
        }
    }

    func saveProfile() async {
        guard !studentNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Le nom de l'eleve est obligatoire."
            return
        }

        guard !selectedBlockers.isEmpty else {
            errorMessage = "Selectionne au moins un point de blocage."
            return
        }

        isBusy = true
        errorMessage = ""
        infoMessage = ""
        defer { isBusy = false }

        do {
            let saved = try await withRetry {
                try await profileRepository.upsertProfile(
                    name: studentNameInput.trimmingCharacters(in: .whitespacesAndNewlines),
                    age: selectedAge,
                    blockers: Array(selectedBlockers).sorted(by: { lhs, rhs in lhs.rawValue < rhs.rawValue }),
                    targetCount: targetExerciseCount,
                    temperature: temperature
                )
            }

            var warningMessages: [String] = []

            do {
                try await withRetry {
                    try await profileRepository.saveDiagnosticResponses(profileID: saved.id, responses: diagnosticResponses)
                }
            } catch {
                warningMessages.append("diagnostic non enregistre")
                errorMessage = "Profil sauvegarde mais diagnostic non enregistre: \(describe(error))"
            }

            // The history table guarantees no duplicate exercise suggestion per profile.
            if !recommendations.isEmpty {
                do {
                    try await withRetry {
                        try await profileRepository.saveRecommendationHistory(profileID: saved.id, ranked: recommendations)
                    }
                } catch {
                    warningMessages.append("historique partiel")
                    errorMessage = "Profil sauvegarde mais historique incomplet: \(describe(error))"
                }
            }

            currentProfile = saved
            let historyCount = try await withRetry {
                try await profileRepository.fetchHistoryExerciseIDs(profileID: saved.id)
            }.count
            infoMessage = warningMessages.isEmpty
                ? "Profil sauvegarde. Historique enregistre: \(historyCount) exercice(s)."
                : "Profil sauvegarde. Historique actuel: \(historyCount) exercice(s)."
            await refreshProfileNames()
        } catch {
            errorMessage = "Echec de sauvegarde: \(describe(error))"
        }
    }

    func recommendExercises() async {
        guard !selectedBlockers.isEmpty else {
            errorMessage = "Selectionne au moins un point de blocage."
            return
        }

        isBusy = true
        errorMessage = ""
        infoMessage = ""
        defer { isBusy = false }

        do {
            let profile: StudentProfile
            if let existing = currentProfile {
                profile = try await withRetry {
                    try await profileRepository.upsertProfile(
                        name: existing.studentName,
                        age: selectedAge,
                        blockers: Array(selectedBlockers).sorted(by: { lhs, rhs in lhs.rawValue < rhs.rawValue }),
                        targetCount: targetExerciseCount,
                        temperature: temperature
                    )
                }
            } else {
                let name = studentNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw RepositoryError.emptyResult("Le nom de l'eleve est requis avant recommandation")
                }
                profile = try await withRetry {
                    try await profileRepository.upsertProfile(
                        name: name,
                        age: selectedAge,
                        blockers: Array(selectedBlockers).sorted(by: { lhs, rhs in lhs.rawValue < rhs.rawValue }),
                        targetCount: targetExerciseCount,
                        temperature: temperature
                    )
                }
            }

            currentProfile = profile
            do {
                try await withRetry {
                    try await profileRepository.saveDiagnosticResponses(profileID: profile.id, responses: diagnosticResponses)
                }
            } catch {
                // Recommendation can still run from current in-memory responses.
                errorMessage = "Diagnostic non enregistre (temporaire): \(describe(error))"
            }

            recommendations = await recommendationService.recommendGuaranteed(
                profile: profile,
                responses: diagnosticResponses
            )

            if recommendations.isEmpty {
                infoMessage = "Aucun exercice disponible pour ces criteres."
            } else {
                do {
                    try await withRetry {
                        try await profileRepository.saveRecommendationHistory(profileID: profile.id, ranked: recommendations)
                    }
                    let historyCount = try await withRetry {
                        try await profileRepository.fetchHistoryExerciseIDs(profileID: profile.id)
                    }.count
                    infoMessage = "\(recommendations.count) exercice(s) proposes. Historique total: \(historyCount)."
                } catch {
                    errorMessage = "Exercices proposes mais historique non enregistre: \(describe(error))"
                    infoMessage = "\(recommendations.count) exercice(s) proposes."
                }
            }
        } catch {
            errorMessage = "Echec de recommandation: \(describe(error))"
        }
    }

    func exportDocx() {
        guard !recommendations.isEmpty else {
            errorMessage = "Aucun exercice a exporter."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "exercices_rumba.docx"
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]

        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try docxExporter.export(
                    exercises: recommendations,
                    to: destination,
                    options: exportOptions
                )
                infoMessage = "Export DOCX termine: \(destination.lastPathComponent)"
            } catch {
                errorMessage = "Echec export DOCX: \(error.localizedDescription)"
            }
        }
    }

    func logout() {
        currentProfile = nil
        recommendations = []
        infoMessage = ""
        errorMessage = ""
    }

    private func apply(profile: StudentProfile) {
        currentProfile = profile
        studentNameInput = profile.studentName
        selectedAge = profile.age
        selectedBlockers = Set(profile.selectedBlockers)
        targetExerciseCount = profile.targetExerciseCount
        temperature = profile.temperature
    }

    private func regenerateDiagnosticResponses() {
        let previous = Dictionary(uniqueKeysWithValues: diagnosticResponses.map { response in
            (response.item.id, response.value)
        })

        diagnosticResponses = selectedBlockers
            .sorted(by: { lhs, rhs in lhs.rawValue < rhs.rawValue })
            .flatMap { type in
                defaultDiagnosticItems(for: type)
            }
            .map { item in
                DiagnosticResponse(
                    id: UUID(),
                    item: item,
                    value: previous[item.id] ?? 0.5
                )
            }
    }

    private func defaultDiagnosticItems(for type: DyslexiaType) -> [DiagnosticItem] {
        let presets: [DyslexiaType: [(String, Double)]] = [
            .phonologique: [
                ("Confusion de sons proches", 1.0),
                ("Difficulte de segmentation syllabique", 0.9),
                ("Erreurs grapheme-phoneme", 1.2)
            ],
            .RAN: [
                ("Lenteur de denomination rapide", 1.1),
                ("Hesitation sur lettres frequentes", 0.8),
                ("Difficulte de lecture a voix haute", 0.9)
            ],
            .work_memory: [
                ("Oublis en cours de consigne", 1.1),
                ("Perte du fil de phrase", 1.0),
                ("Charge cognitive elevee", 0.8)
            ],
            .visuo_spatiale: [
                ("Sauts de ligne", 1.2),
                ("Confusions visuelles", 0.9),
                ("Reperage spatial faible", 0.8)
            ],
            .oculomoteur: [
                ("Retour arriere frequent", 1.1),
                ("Fatigue visuelle", 0.8),
                ("Fixation instable", 0.9)
            ],
            .metacognitif: [
                ("Auto-correction faible", 0.8),
                ("Strategies de lecture limitees", 1.0),
                ("Planification fragile", 0.9)
            ],
            .holistique: [
                ("Difficulte de vision globale", 0.9),
                ("Integration lente des indices", 0.9),
                ("Generalisation fragile", 0.8)
            ],
            .deep_mixte: [
                ("Indices mixtes severes", 1.2),
                ("Variabilite des erreurs", 1.0),
                ("Automatisation incomplete", 1.1)
            ],
            .double_deficit: [
                ("Double deficit lecture-rapidite", 1.2),
                ("Lenteur persistante", 1.0),
                ("Erreur frequente", 1.0)
            ],
            .M_type: [
                ("Precision et vitesse faibles", 1.1),
                ("Lecture hachee", 0.9),
                ("Consolidation instable", 1.0)
            ],
            .neurocognitig_multiple: [
                ("Deficits combines", 1.2),
                ("Attention fragile", 1.0),
                ("Memoire et langage impactes", 1.1)
            ]
        ]

        let rows = presets[type] ?? []
        return rows.enumerated().map { index, tuple in
            DiagnosticItem(
                id: UUID(uuidString: deterministicUUIDSeed(type: type, index: index)) ?? UUID(),
                dyslexiaType: type,
                prompt: tuple.0,
                weight: tuple.1
            )
        }
    }

    private func deterministicUUIDSeed(type: DyslexiaType, index: Int) -> String {
        let base = abs("\(type.rawValue)-\(index)".hashValue)
        let padded = String(base, radix: 16).prefix(12)
        let value = String(padded).padding(toLength: 12, withPad: "0", startingAt: 0)
        return "00000000-0000-0000-0000-\(value)"
    }

    @MainActor
    private func withRetry<T>(
        attempts: Int = 3,
        delayNanoseconds: UInt64 = 250_000_000,
        operation: @MainActor () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for index in 0..<max(1, attempts) {
            do {
                return try await operation()
            } catch {
                lastError = error
                if index < attempts - 1 {
                    try? await Task.sleep(nanoseconds: delayNanoseconds * UInt64(index + 1))
                }
            }
        }

        throw lastError ?? RepositoryError.emptyResult("Erreur inconnue")
    }

    private func describe(_ error: Error) -> String {
        if let pgError = error as? PSQLError {
            var details: [String] = []
            details.append("code=\(pgError.code)")

            if let info = pgError.serverInfo {
                if let state = info[.sqlState] { details.append("sqlState=\(state)") }
                if let message = info[.message] { details.append("message=\(message)") }
                if let detail = info[.detail] { details.append("detail=\(detail)") }
                if let hint = info[.hint] { details.append("hint=\(hint)") }
                if let table = info[.tableName] { details.append("table=\(table)") }
                if let column = info[.columnName] { details.append("column=\(column)") }
                if let constraint = info[.constraintName] { details.append("constraint=\(constraint)") }
            }

            if let underlying = pgError.underlying {
                details.append("underlying=\(String(reflecting: underlying))")
            }

            return details.joined(separator: " | ")
        }

        let localized = error.localizedDescription
        let verbose = String(describing: error)
        if localized == verbose || verbose.isEmpty {
            return localized
        }
        return "\(localized) (\(verbose))"
    }
}
