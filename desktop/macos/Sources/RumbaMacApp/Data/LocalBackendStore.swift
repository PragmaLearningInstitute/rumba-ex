import Foundation

actor LocalBackendStore {
    static let shared = LocalBackendStore()

    private let fileURL: URL
    private var state: PersistedState

    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folderURL = appSupport.appendingPathComponent("RumbaMacApp", isDirectory: true)

        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.fileURL = folderURL.appendingPathComponent("local_backend.json")
        self.state = PersistedState()

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            self.state = decoded
        }
    }

    func listProfileNames() -> [String] {
        state.profiles.values
            .map { $0.studentName }
            .sorted()
    }

    func loadProfile(named name: String) -> StudentProfile? {
        let normalized = normalize(name)
        guard let persisted = state.profiles.values.first(where: { profile in
            normalize(profile.studentName) == normalized
        }) else {
            return nil
        }
        return persisted.toModel
    }

    func createProfile(named name: String, age: Int = 9) throws -> StudentProfile {
        if let existing = loadProfile(named: name) {
            return existing
        }

        let profile = StudentProfile(
            id: UUID(),
            studentName: name,
            age: age,
            selectedBlockers: [.phonologique],
            targetExerciseCount: 3,
            temperature: 0.8
        )

        state.profiles[profile.id.uuidString] = PersistedProfile(from: profile)
        try persist()
        return profile
    }

    func upsertProfile(
        name: String,
        age: Int,
        blockers: [DyslexiaType],
        targetCount: Int,
        temperature: Double
    ) throws -> StudentProfile {
        let profile = loadProfile(named: name) ?? StudentProfile(
            id: UUID(),
            studentName: name,
            age: age,
            selectedBlockers: blockers,
            targetExerciseCount: targetCount,
            temperature: temperature
        )

        let updated = StudentProfile(
            id: profile.id,
            studentName: name,
            age: age,
            selectedBlockers: blockers,
            targetExerciseCount: targetCount,
            temperature: temperature
        )

        state.profiles[updated.id.uuidString] = PersistedProfile(from: updated)
        try persist()
        return updated
    }

    func saveDiagnosticResponses(profileID: UUID, responses: [DiagnosticResponse]) throws {
        state.diagnosticResponses[profileID.uuidString] = responses.map(PersistedDiagnosticResponse.init(from:))
        try persist()
    }

    func fetchHistoryExerciseIDs(profileID: UUID) -> Set<UUID> {
        Set((state.historyByProfile[profileID.uuidString] ?? []).compactMap(UUID.init(uuidString:)))
    }

    func saveRecommendationHistory(profileID: UUID, ranked: [RankedExercise]) throws {
        var existing = Set(state.historyByProfile[profileID.uuidString] ?? [])
        ranked.forEach { existing.insert($0.exercise.id.uuidString) }
        state.historyByProfile[profileID.uuidString] = Array(existing)
        try persist()
    }

    func fetchPrecomputedSimilarities(type: DyslexiaType, age: Int) -> [UUID: Double] {
        let candidates = seedExercises().filter { exercise in
            exercise.ageMin <= age && exercise.ageMax >= age
        }

        return Dictionary(uniqueKeysWithValues: candidates.map { exercise in
            (exercise.id, similarity(type: type, age: age, exercise: exercise))
        })
    }

    func fetchDynamicSimilarities(type: DyslexiaType, age: Int) -> [UUID: Double] {
        // Local mode uses the same deterministic strategy for precomputed and dynamic similarities.
        fetchPrecomputedSimilarities(type: type, age: age)
    }

    func fetchExercises(ids: [UUID]) -> [UUID: Exercise] {
        let idSet = Set(ids)
        let selected = seedExercises().filter { idSet.contains($0.id) }
        return Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private func similarity(type: DyslexiaType, age: Int, exercise: Exercise) -> Double {
        let affinity = domainAffinity[type]?[exercise.domain] ?? 0.40
        let targetLevel = min(6.0, max(1.0, 1.0 + (Double(age - 6) / 2.0)))
        let levelDistance = abs(Double(exercise.level.order) - targetLevel)
        let levelScore = max(0.0, 1.0 - (levelDistance * 0.18))
        let jitter = tinyJitter(type: type, exerciseID: exercise.id)

        let raw = (0.58 * affinity) + (0.34 * levelScore) + (0.08 * jitter)
        return RecommendationMath.bounded(raw)
    }

    private func tinyJitter(type: DyslexiaType, exerciseID: UUID) -> Double {
        let scalar = "\(type.rawValue)-\(exerciseID.uuidString)".unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return Double(scalar % 17) / 16.0
    }

    private func seedExercises() -> [Exercise] {
        [
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE001")!,
                title: "Fusion syllabique rapide",
                content: "Lis les syllabes et forme le mot final: pa - ni - er, cha - peau, ba - teau.",
                domain: .phonemique,
                level: .niveau1,
                ageMin: 6,
                ageMax: 9,
                correctAnswer: "panier, chapeau, bateau",
                hint: "Assemble chaque syllabe dans l'ordre."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE002")!,
                title: "Discrimination de sons proches",
                content: "Entoure le mot entendu: bol / vol, pain / bain, tas / das.",
                domain: .phonemique,
                level: .niveau2,
                ageMin: 6,
                ageMax: 10,
                correctAnswer: "selon dictée de l'enseignant",
                hint: "Concentre-toi sur le premier son."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE003")!,
                title: "Lecture minute",
                content: "Lis la liste de 20 mots fréquents en 60 secondes et note le score.",
                domain: .orthographique,
                level: .niveau2,
                ageMin: 7,
                ageMax: 12,
                correctAnswer: "score personnel",
                hint: "Cherche la fluidité plutôt que la vitesse brute."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE004")!,
                title: "Mots outils visuels",
                content: "Recopie sans faute: toujours, beaucoup, monsieur, aujourd'hui, encore.",
                domain: .orthographique,
                level: .niveau3,
                ageMin: 8,
                ageMax: 13,
                correctAnswer: "orthographe exacte",
                hint: "Observe les lettres muettes."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE005")!,
                title: "Phrases a remettre en ordre",
                content: "Replace les groupes de mots pour former une phrase correcte.",
                domain: .syntaxe,
                level: .niveau3,
                ageMin: 8,
                ageMax: 14,
                correctAnswer: "phrase syntaxiquement correcte",
                hint: "Commence par trouver le verbe."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE006")!,
                title: "Accords sujet-verbe",
                content: "Choisis la bonne forme: Les enfants (joue/jouent) dans la cour.",
                domain: .syntaxe,
                level: .niveau4,
                ageMin: 9,
                ageMax: 14,
                correctAnswer: "jouent",
                hint: "Le sujet est au pluriel."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE007")!,
                title: "Compréhension flash",
                content: "Lis un court texte puis réponds a 3 questions factuelles.",
                domain: .comprehension,
                level: .niveau2,
                ageMin: 7,
                ageMax: 11,
                correctAnswer: "reponses basees sur le texte",
                hint: "Relis la phrase clé avant de répondre."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE008")!,
                title: "Inference guidée",
                content: "Déduis l'émotion du personnage a partir des indices du texte.",
                domain: .comprehension,
                level: .niveau5,
                ageMin: 10,
                ageMax: 14,
                correctAnswer: "justification argumentée",
                hint: "Appuie-toi sur deux indices explicites."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE009")!,
                title: "Copie active",
                content: "Copie un paragraphe court en marquant les ponctuations en couleur.",
                domain: .ecriture,
                level: .niveau2,
                ageMin: 7,
                ageMax: 11,
                correctAnswer: "copie fidèle",
                hint: "Pause a chaque virgule."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE010")!,
                title: "Dictée segmentée",
                content: "Écris la phrase dictée en séparant d'abord les groupes de souffle.",
                domain: .ecriture,
                level: .niveau4,
                ageMin: 9,
                ageMax: 14,
                correctAnswer: "phrase exacte",
                hint: "Découpe en groupes avant d'écrire."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE011")!,
                title: "Balayage visuel de ligne",
                content: "Repère la lettre cible dans une grille en suivant la ligne sans saut.",
                domain: .phonemique,
                level: .niveau1,
                ageMin: 6,
                ageMax: 10,
                correctAnswer: "nombre correct de lettres repérées",
                hint: "Utilise ton doigt pour guider le regard."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE012")!,
                title: "Mémoire de consigne",
                content: "Lis trois consignes puis exécute-les dans le bon ordre.",
                domain: .comprehension,
                level: .niveau3,
                ageMin: 8,
                ageMax: 13,
                correctAnswer: "ordre respecté",
                hint: "Répète mentalement chaque étape."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE013")!,
                title: "Texte troué morphologique",
                content: "Complète les mots manquants avec le bon suffixe.",
                domain: .orthographique,
                level: .niveau5,
                ageMin: 10,
                ageMax: 14,
                correctAnswer: "suffixes adaptés",
                hint: "Repère la famille de mots."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE014")!,
                title: "Lecture expressive",
                content: "Lis le texte en respectant ponctuation et intonation.",
                domain: .syntaxe,
                level: .niveau4,
                ageMin: 9,
                ageMax: 14,
                correctAnswer: "lecture fluide et ponctuée",
                hint: "Prends une respiration au point."
            ),
            Exercise(
                id: UUID(uuidString: "A30089C6-CF9F-43F5-BFC6-AC995EBCE015")!,
                title: "Résumé en 3 phrases",
                content: "Résume le texte lu en exactement trois phrases simples.",
                domain: .comprehension,
                level: .niveau6,
                ageMin: 11,
                ageMax: 14,
                correctAnswer: "3 phrases cohérentes",
                hint: "Conserve idée principale + 2 détails."
            )
        ]
    }

    private let domainAffinity: [DyslexiaType: [ExerciseDomain: Double]] = [
        .phonologique: [.phonemique: 0.95, .orthographique: 0.70, .comprehension: 0.50, .syntaxe: 0.40, .ecriture: 0.42],
        .RAN: [.orthographique: 0.85, .phonemique: 0.78, .comprehension: 0.52, .syntaxe: 0.46, .ecriture: 0.54],
        .work_memory: [.comprehension: 0.92, .syntaxe: 0.70, .ecriture: 0.66, .orthographique: 0.48, .phonemique: 0.44],
        .visuo_spatiale: [.phonemique: 0.88, .orthographique: 0.74, .ecriture: 0.64, .syntaxe: 0.45, .comprehension: 0.43],
        .oculomoteur: [.phonemique: 0.84, .orthographique: 0.76, .comprehension: 0.62, .syntaxe: 0.46, .ecriture: 0.45],
        .metacognitif: [.comprehension: 0.93, .syntaxe: 0.72, .ecriture: 0.68, .orthographique: 0.54, .phonemique: 0.41],
        .holistique: [.comprehension: 0.84, .syntaxe: 0.76, .orthographique: 0.60, .ecriture: 0.57, .phonemique: 0.49],
        .deep_mixte: [.orthographique: 0.82, .comprehension: 0.82, .phonemique: 0.75, .syntaxe: 0.68, .ecriture: 0.63],
        .double_deficit: [.phonemique: 0.90, .orthographique: 0.88, .comprehension: 0.62, .syntaxe: 0.52, .ecriture: 0.49],
        .M_type: [.phonemique: 0.84, .orthographique: 0.83, .ecriture: 0.60, .syntaxe: 0.56, .comprehension: 0.50],
        .neurocognitig_multiple: [.comprehension: 0.86, .orthographique: 0.76, .syntaxe: 0.74, .ecriture: 0.69, .phonemique: 0.61]
    ]
}

private struct PersistedState: Codable {
    var profiles: [String: PersistedProfile] = [:]
    var diagnosticResponses: [String: [PersistedDiagnosticResponse]] = [:]
    var historyByProfile: [String: [String]] = [:]
}

private struct PersistedProfile: Codable {
    let id: UUID
    let studentName: String
    let age: Int
    let selectedBlockers: [String]
    let targetExerciseCount: Int
    let temperature: Double

    init(from model: StudentProfile) {
        self.id = model.id
        self.studentName = model.studentName
        self.age = model.age
        self.selectedBlockers = model.selectedBlockers.map(\.rawValue)
        self.targetExerciseCount = model.targetExerciseCount
        self.temperature = model.temperature
    }

    var toModel: StudentProfile {
        StudentProfile(
            id: id,
            studentName: studentName,
            age: age,
            selectedBlockers: selectedBlockers.compactMap(DyslexiaType.init(rawValue:)),
            targetExerciseCount: targetExerciseCount,
            temperature: temperature
        )
    }
}

private struct PersistedDiagnosticResponse: Codable {
    let id: UUID
    let itemID: UUID
    let dyslexiaType: String
    let prompt: String
    let weight: Double
    let value: Double

    init(from model: DiagnosticResponse) {
        self.id = model.id
        self.itemID = model.item.id
        self.dyslexiaType = model.item.dyslexiaType.rawValue
        self.prompt = model.item.prompt
        self.weight = model.item.weight
        self.value = model.value
    }
}
