import SwiftUI

enum MeetingNotchTheme {
    static let panelWidth: CGFloat = 424
    static let detailPanelWidth: CGFloat = 520
    static let panelMinimumWidth: CGFloat = 320
    static let panelHorizontalPadding: CGFloat = 8
    static let panelVerticalPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 14
    static let contentSpacing: CGFloat = 10
    static let itemSpacing: CGFloat = 10
    static let surfaceRadius: CGFloat = 12
    static let controlRadius: CGFloat = 9
    static let controlHeight: CGFloat = 32
    static let iconSize: CGFloat = 12

    static let surface = Color.white.opacity(0.045)
    static let surfaceHover = Color.white.opacity(0.075)
    static let elevatedSurface = Color.white.opacity(0.065)
    static let hairline = Color.white.opacity(0.08)
    static let subtleHairline = Color.white.opacity(0.055)

    static let accent = Color(red: 1.0, green: 0.45, blue: 0.12)
    static let success = Color(red: 0.20, green: 0.82, blue: 0.45)

    static var titleFont: Font {
        .system(size: 14, weight: .semibold, design: .default)
    }

    static var sectionTitleFont: Font {
        .system(size: 11, weight: .semibold, design: .default)
    }

    static var rowTitleFont: Font {
        .system(size: 13, weight: .medium, design: .default)
    }

    static var bodyFont: Font {
        .system(size: 12, weight: .regular, design: .default)
    }

    static var metadataFont: Font {
        .system(size: 10, weight: .medium, design: .monospaced)
    }

    static var dataFont: Font {
        .system(size: 11, weight: .semibold, design: .monospaced)
    }

    static var controlFont: Font {
        .system(size: 12, weight: .semibold, design: .default)
    }
}

struct MeetingNotchIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color = .secondary
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: MeetingNotchTheme.iconSize, weight: .semibold))
            .foregroundStyle(isActive ? tint : tint.opacity(0.82))
            .frame(
                width: MeetingNotchTheme.controlHeight,
                height: MeetingNotchTheme.controlHeight
            )
            .contentShape(Rectangle())
            .background(
                isActive
                    ? tint.opacity(0.14)
                    : Color.white.opacity(configuration.isPressed ? 0.09 : 0.045),
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
                .stroke(
                    isActive ? tint.opacity(0.24) : MeetingNotchTheme.subtleHairline,
                    lineWidth: 1
                )
            }
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
