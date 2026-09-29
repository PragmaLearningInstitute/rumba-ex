import Foundation

enum DyslexiaType: String, CaseIterable, Codable, Identifiable {
    case phonologique
    case RAN
    case work_memory
    case visuo_spatiale
    case oculomoteur
    case metacognitif
    case holistique
    case deep_mixte
    case double_deficit
    case M_type
    case neurocognitig_multiple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phonologique: return "Phonologique"
        case .RAN: return "RAN"
        case .work_memory: return "Mémoire de travail"
        case .visuo_spatiale: return "Visuo-spatiale"
        case .oculomoteur: return "Oculomoteur"
        case .metacognitif: return "Métacognitif"
        case .holistique: return "Holistique"
        case .deep_mixte: return "Deep mixte"
        case .double_deficit: return "Double déficit"
        case .M_type: return "M-Type"
        case .neurocognitig_multiple: return "Neurocognitif multiple"
        }
    }
}

enum ExerciseDomain: String, CaseIterable, Codable {
    case phonemique = "Phonémique"
    case orthographique = "Orthographique"
    case syntaxe = "Syntaxe"
    case comprehension = "Comprehension"
    case ecriture = "Ecriture"
}

enum ExerciseLevel: String, CaseIterable, Codable {
    case niveau1 = "Niveau1"
    case niveau2 = "Niveau2"
    case niveau3 = "Niveau3"
    case niveau4 = "Niveau4"
    case niveau5 = "Niveau5"
    case niveau6 = "Niveau6"

    var order: Int {
        switch self {
        case .niveau1: return 1
        case .niveau2: return 2
        case .niveau3: return 3
        case .niveau4: return 4
        case .niveau5: return 5
        case .niveau6: return 6
        }
    }
}

struct StudentProfile: Identifiable, Equatable {
    let id: UUID
    var studentName: String
    var age: Int
    var selectedBlockers: [DyslexiaType]
    var targetExerciseCount: Int
    var temperature: Double
}

struct DiagnosticItem: Identifiable, Hashable {
    let id: UUID
    let dyslexiaType: DyslexiaType
    let prompt: String
    let weight: Double
}

struct DiagnosticResponse: Identifiable {
    let id: UUID
    let item: DiagnosticItem
    var value: Double
}

struct Exercise: Identifiable, Equatable {
    let id: UUID
    let title: String
    let content: String
    let domain: ExerciseDomain
    let level: ExerciseLevel
    let ageMin: Int
    let ageMax: Int
    let correctAnswer: String
    let hint: String?
}

struct RankedExercise: Identifiable, Equatable {
    let id: UUID
    let exercise: Exercise
    let relevance: Double
    let authority: Double
    let diversity: Double
    let finalScore: Double
}

enum ExportFont: String, CaseIterable, Identifiable {
    case avenirNext = "Avenir Next"
    case arial = "Arial"
    case openDyslexie = "OpenDyslexie"

    var id: String { rawValue }

    var wordFontName: String {
        switch self {
        case .avenirNext:
            return "Avenir Next"
        case .arial:
            return "Arial"
        case .openDyslexie:
            // If OpenDyslexic is installed, Word will fallback correctly.
            return "OpenDyslexic"
        }
    }
}

struct ExportOptions {
    var font: ExportFont = .avenirNext
    var size: Int = 12
}
