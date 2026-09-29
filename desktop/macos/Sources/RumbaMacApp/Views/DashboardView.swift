import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private let grid = [
        GridItem(.adaptive(minimum: 160), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                settingsPanel
                recommendationPanel
            }

            StatusBannerView()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 16)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text("Tableau de bord")
                        .font(AppTheme.titleFont(30))
                        .foregroundStyle(AppTheme.primary)
                }

                if let profile = viewModel.currentProfile {
                    Text("Profil actif: \(profile.studentName)")
                        .font(AppTheme.bodyFont(14))
                        .foregroundStyle(.black.opacity(0.75))
                }

                Text(viewModel.backendStatusText)
                    .font(AppTheme.bodyFont(12))
                    .foregroundStyle(.black.opacity(0.65))
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Sauvegarder profil") {
                    Task { await viewModel.saveProfile() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.success)

                Button("Obtenir les exercices") {
                    Task { await viewModel.recommendExercises() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)

                Button("Se deconnecter") {
                    viewModel.logout()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.warning)
            }
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Text("Parametres").foregroundStyle(.black)) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Age")
                                .font(AppTheme.bodyFont(14))
                                .foregroundStyle(.black)
                            Spacer()
                            Text("\(viewModel.selectedAge) ans")
                                .font(AppTheme.bodyFont(14))
                                .foregroundStyle(.black.opacity(0.75))
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.selectedAge) },
                                set: { newValue in viewModel.selectedAge = Int(newValue.rounded()) }
                            ),
                            in: 6...14,
                            step: 1
                        )
                        .tint(AppTheme.primary)

                        HStack {
                            Text("Nombre d'exercices")
                                .font(AppTheme.bodyFont(14))
                                .foregroundStyle(.black)
                            Spacer()
                            Stepper(value: $viewModel.targetExerciseCount, in: 1...5) {
                                Text("\(viewModel.targetExerciseCount)")
                                    .font(AppTheme.bodyFont(14))
                                    .foregroundStyle(.black)
                            }
                            .frame(width: 140)
                        }

                        HStack {
                            Text("Temperature softmax")
                                .font(AppTheme.bodyFont(14))
                                .foregroundStyle(.black)
                            Spacer()
                            Text(String(format: "%.2f", viewModel.temperature))
                                .font(AppTheme.monoFont(12))
                                .foregroundStyle(.black.opacity(0.75))
                        }

                        Slider(value: $viewModel.temperature, in: 0.1...3.0, step: 0.05)
                            .tint(AppTheme.accent)
                    }
                    .padding(.top, 4)
                }

                GroupBox(label: Text("Points de blocage").foregroundStyle(.black)) {
                    LazyVGrid(columns: grid, spacing: 10) {
                        ForEach(DyslexiaType.allCases) { type in
                            BlockerChip(
                                label: type.label,
                                selected: viewModel.selectedBlockers.contains(type)
                            ) {
                                if viewModel.selectedBlockers.contains(type) {
                                    // Keep at least one blocker selected, without remove/insert cycles.
                                    if viewModel.selectedBlockers.count > 1 {
                                        viewModel.selectedBlockers.remove(type)
                                    }
                                } else {
                                    viewModel.selectedBlockers.insert(type)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox(label: Text("Items diagnostiques").foregroundStyle(.black)) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.diagnosticResponses) { response in
                            let item = response.item
                            let responseID = response.id
                            VStack(alignment: .leading, spacing: 6) {
                                Text("[\(item.dyslexiaType.label)] \(item.prompt)")
                                    .font(AppTheme.bodyFont(13))

                                HStack {
                                    Text("Faible")
                                        .font(AppTheme.bodyFont(11))
                                        .foregroundStyle(.black.opacity(0.7))

                                    Slider(
                                        value: Binding(
                                            get: {
                                                viewModel.diagnosticResponses.first(where: { $0.id == responseID })?.value ?? 0.5
                                            },
                                            set: { newValue in
                                                if let index = viewModel.diagnosticResponses.firstIndex(where: { $0.id == responseID }) {
                                                    viewModel.diagnosticResponses[index].value = newValue
                                                }
                                            }
                                        ),
                                        in: 0...1,
                                        step: 0.05
                                    )
                                    .tint(AppTheme.primary)

                                    Text("Eleve")
                                        .font(AppTheme.bodyFont(11))
                                        .foregroundStyle(.black.opacity(0.7))
                                }
                            }
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.primary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 620)
        .foregroundStyle(.black)
    }

    private var recommendationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exercices recommandes")
                .font(AppTheme.titleFont(24))
                .foregroundStyle(AppTheme.primary)

            if viewModel.recommendations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 34))
                        .foregroundStyle(AppTheme.accent)
                    Text("Aucun exercice pour le moment")
                        .font(AppTheme.bodyFont(15))
                        .foregroundStyle(.black.opacity(0.75))
                    Text("Lance la recommandation pour obtenir le top exercices personalise.")
                        .font(AppTheme.bodyFont(13))
                        .foregroundStyle(.black.opacity(0.65))
                    Button("Obtenir les exercices") {
                        Task { await viewModel.recommendExercises() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.primary.opacity(0.12), lineWidth: 1)
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(viewModel.recommendations) { ranked in
                            RecommendationCard(ranked: ranked)
                        }
                    }
                }
                .frame(maxHeight: 430)

                GroupBox(label: Text("Export Word").foregroundStyle(.black)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Police", selection: $viewModel.exportOptions.font) {
                            ForEach(ExportFont.allCases) { font in
                                Text(font.rawValue).tag(font)
                            }
                        }

                        HStack {
                            Text("Taille")
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.exportOptions.size) },
                                    set: { value in viewModel.exportOptions.size = Int(value.rounded()) }
                                ),
                                in: 11...15,
                                step: 1
                            )
                            Text("\(viewModel.exportOptions.size) pt")
                                .font(AppTheme.monoFont(11))
                                .frame(width: 50)
                        }

                        Text("Interligne impose: 1.5 | Reponses sur page separee")
                            .font(AppTheme.bodyFont(11))
                            .foregroundStyle(.black.opacity(0.7))

                        Button("Generer .docx") {
                            viewModel.exportDocx()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct BlockerChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTheme.bodyFont(12))
                .foregroundStyle(selected ? .white : AppTheme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(selected ? AppTheme.primary : Color.white.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RecommendationCard: View {
    let ranked: RankedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ranked.exercise.title)
                .font(AppTheme.bodyFont(16))
                .foregroundStyle(AppTheme.primary)

            Text(ranked.exercise.content)
                .font(AppTheme.bodyFont(13))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.black)

            HStack {
                tag("Domain: \(ranked.exercise.domain.rawValue)")
                tag("Level: \(ranked.exercise.level.rawValue)")
                Spacer()
                tag(String(format: "F=%.3f", ranked.finalScore))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.monoFont(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
    }
}
