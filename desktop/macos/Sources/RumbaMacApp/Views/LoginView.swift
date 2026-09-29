import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Rumba macOS")
                    .font(AppTheme.titleFont(38))
                    .foregroundStyle(AppTheme.primary)
            }

            Text("Crée un profil ou connecte-toi a un profil existant en saisissant le nom de l'eleve.")
                .font(AppTheme.bodyFont(17))
                .foregroundStyle(AppTheme.primary.opacity(0.72))

            Text(viewModel.backendStatusText)
                .font(AppTheme.bodyFont(13))
                .foregroundStyle(.black.opacity(0.72))

            HStack(spacing: 12) {
                TextField("Nom de l'eleve", text: $viewModel.studentNameInput)
                    .textFieldStyle(.plain)
                    .font(AppTheme.bodyFont(16))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.primary.opacity(0.18), lineWidth: 1)
                    )

                Button(action: {
                    Task { await viewModel.loginExistingProfile() }
                }) {
                    if viewModel.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Se connecter")
                            .font(AppTheme.bodyFont(15))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .disabled(viewModel.isBusy || !viewModel.typedProfileExists)

                if viewModel.hasStudentNameInput && !viewModel.typedProfileExists {
                    Button(action: {
                        Task { await viewModel.createProfileFromInput() }
                    }) {
                        Text("Creer le profil")
                            .font(AppTheme.bodyFont(15))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.success)
                    .disabled(viewModel.isBusy)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            if viewModel.hasStudentNameInput {
                Text(viewModel.typedProfileExists
                     ? "Profil trouve: clique sur \"Se connecter\"."
                     : "Profil introuvable: clique sur \"Creer le profil\".")
                    .font(AppTheme.bodyFont(13))
                    .foregroundStyle(viewModel.typedProfileExists ? AppTheme.success : AppTheme.warning)
            }

            if !viewModel.knownProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profils existants")
                        .font(AppTheme.bodyFont(15))
                        .foregroundStyle(AppTheme.primary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.knownProfiles, id: \.self) { name in
                                Button(name) {
                                    viewModel.studentNameInput = name
                                }
                                .buttonStyle(.bordered)
                                .font(AppTheme.bodyFont(13))
                            }
                        }
                    }
                }
            }

            StatusBannerView()

            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(maxWidth: 760, maxHeight: 420, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 30, x: 0, y: 18)
    }
}
