import AppKit
import SwiftUI

enum AppTheme {
    static let accent = Color(nsColor: .controlAccentColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.65)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
}

extension View {
    func appCard(cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(AppTheme.card, in: shape)
            .overlay(shape.strokeBorder(AppTheme.border, lineWidth: 1))
    }
}
