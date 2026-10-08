import SwiftUI

struct DisplayGlyph: View {
    let display: DisplayDevice
    let number: Int

    private var aspect: CGFloat {
        let size = display.metadata
        let ratio = size.physicalWidthMM > 0 && size.physicalHeightMM > 0
            ? size.physicalWidthMM / size.physicalHeightMM
            : display.frame.width / max(display.frame.height, 1)
        return display.rotation.truncatingRemainder(dividingBy: 180) == 90 ? 1 / max(ratio, 0.1) : max(ratio, 0.1)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(String(number))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .frame(width: 34, height: min(38, max(16, 34 / aspect)))
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.6), lineWidth: 1.5))
            RoundedRectangle(cornerRadius: 1)
                .fill(.primary.opacity(0.6))
                .frame(width: display.isBuiltin ? 34 : 12, height: 2)
        }
        .frame(width: 38, height: 44)
        .accessibilityHidden(true)
    }
}

struct DisplayArrangementView: View {
    let displays: [DisplayDevice]
    @Binding var selectedDisplayID: UInt32?
    let language: AppLanguage

    var body: some View {
        let bounds = displays.reduce(CGRect.null) { $0.union($1.frame.cgRect) }
        GeometryReader { geometry in
            if !bounds.isNull, bounds.width > 0, bounds.height > 0 {
                let scale = min(geometry.size.width / bounds.width, geometry.size.height / bounds.height)
                let offsetX = (geometry.size.width - bounds.width * scale) / 2
                let offsetY = (geometry.size.height - bounds.height * scale) / 2
                ForEach(displays.indices, id: \.self) { index in
                    let display = displays[index]
                    let selected = display.id == selectedDisplayID
                    Button {
                        selectedDisplayID = display.id
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                Text(String(index + 1))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                if display.metadata.isMain {
                                    Image(systemName: "star.fill").font(.system(size: 8))
                                }
                            }
                            Text(display.shortName(language: language))
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                        .padding(3)
                        .frame(width: display.frame.width * scale, height: display.frame.height * scale)
                        .foregroundStyle(selected ? AppTheme.accent : .primary)
                        .background(selected ? AppTheme.accent.opacity(0.10) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? AppTheme.accent : AppTheme.border, lineWidth: selected ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: offsetX + (display.frame.x - bounds.minX + display.frame.width / 2) * scale,
                              y: offsetY + (display.frame.y - bounds.minY + display.frame.height / 2) * scale)
                    .accessibilityLabel("\(display.shortName(language: language)) · \(L10n.t("ui.screen", language)) \(index + 1)\(display.metadata.isMain ? " · " + L10n.t("display.main", language) : "")")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help(display.shortName(language: language) + (display.metadata.isMain ? " · " + L10n.t("display.main", language) : ""))
                }
            }
        }
        .frame(height: 74)
    }
}
