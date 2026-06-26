import AppKit
import SwiftUI

enum AppTheme {
    static let accent = Color(red: 1.0, green: 0.48, blue: 0.07)
    static let background = dynamic(
        light: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.94, alpha: 1),
        dark: NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.24, alpha: 1)
    )
    static let sidebar = dynamic(
        light: NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.88, alpha: 1),
        dark: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.13, alpha: 1)
    )
    static let card = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.055)
    )
    static let cardStrong = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.78),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.085)
    )
    static let controlFill = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.075),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.24)
    )
    static let border = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.12),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )
    static let primaryText = dynamic(
        light: NSColor(calibratedWhite: 0.08, alpha: 0.94),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.92)
    )
    static let secondaryText = dynamic(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.56),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.62)
    )
    static let glassOverlayStart = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        dark: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.13, alpha: 0.82)
    )
    static let glassOverlayEnd = dynamic(
        light: NSColor(calibratedWhite: 0.95, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.11, alpha: 0.88)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}
