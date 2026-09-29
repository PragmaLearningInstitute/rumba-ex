import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: animateGradient
                    ? [AppTheme.backgroundTop, AppTheme.backgroundBottom, AppTheme.backgroundTop.opacity(0.9)]
                    : [AppTheme.backgroundBottom, AppTheme.backgroundTop, AppTheme.backgroundBottom.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animateGradient)

            Group {
                if viewModel.isLoggedIn {
                    DashboardView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    LoginView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .padding(24)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: viewModel.isLoggedIn)
        }
        .onAppear {
            animateGradient = true
        }
    }
}
