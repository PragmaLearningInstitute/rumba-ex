import SwiftUI

enum AppTheme {
    static let backgroundTop = Color(red: 0.95, green: 0.97, blue: 1.0)
    static let backgroundBottom = Color(red: 0.87, green: 0.95, blue: 0.92)
    static let primary = Color(red: 0.09, green: 0.34, blue: 0.55)
    static let accent = Color(red: 0.96, green: 0.58, blue: 0.30)
    static let card = Color.white.opacity(0.84)
    static let success = Color(red: 0.18, green: 0.63, blue: 0.35)
    static let warning = Color(red: 0.86, green: 0.35, blue: 0.23)

    static func titleFont(_ size: CGFloat = 28) -> Font {
        .custom("Avenir Next Demi Bold", size: size)
    }

    static func bodyFont(_ size: CGFloat = 15) -> Font {
        .custom("Avenir Next", size: size)
    }

    static func monoFont(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}
