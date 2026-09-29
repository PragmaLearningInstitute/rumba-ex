import SwiftUI

struct StatusBannerView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Group {
            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .font(AppTheme.bodyFont(13))
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.warning)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if !viewModel.infoMessage.isEmpty {
                Text(viewModel.infoMessage)
                    .font(AppTheme.bodyFont(13))
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.success)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.infoMessage)
    }
}
