import SwiftUI

@main
struct RumbaMacApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .preferredColorScheme(.light)
                .frame(minWidth: 1080, minHeight: 760)
        }
        .windowStyle(.titleBar)
    }
}
