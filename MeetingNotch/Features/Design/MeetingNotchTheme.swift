import SwiftUI

enum MeetingNotchTheme {
    static let panelWidth: CGFloat = 600
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
    static let tabHeight: CGFloat = 34
    static let tabBarPadding: CGFloat = 3
    static let iconSize: CGFloat = 12

    // Legacy/detail surfaces remain semantic. The Figma main panel defines an explicitly
    // dark canvas, so both physical-notch and floating presentations resolve to dark mode.
    static let surface = Color.primary.opacity(0.065)
    static let surfaceHover = Color.primary.opacity(0.105)
    static let elevatedSurface = Color.primary.opacity(0.095)
    static let hairline = Color.primary.opacity(0.14)
    static let subtleHairline = Color.primary.opacity(0.09)

    static let inactiveTabForegroundOpacity = 0.68
    static let inactiveTabHoverForegroundOpacity = 0.88
    static let activeTabFillOpacity = 0.11

    static let inactiveTabForeground = Color.primary.opacity(inactiveTabForegroundOpacity)
    static let inactiveTabHoverForeground = Color.primary.opacity(inactiveTabHoverForegroundOpacity)
    static let activeTabForeground = Color.primary
    static let activeTabFill = Color.primary.opacity(activeTabFillOpacity)
    static let tabTrackFill = Color.primary.opacity(0.055)

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

    enum MainPanel {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 20
        static let contentSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 4
        static let itemSpacing: CGFloat = 10

        static let panelRadius: CGFloat = 24
        static let surfaceRadius: CGFloat = 22
        static let capsuleRadius: CGFloat = 16
        static let compactRadius: CGFloat = 6

        static let tabHeight: CGFloat = 32
        static let rowHeight: CGFloat = 58
        static let iconSize: CGFloat = 20
        static let smallIconSize: CGFloat = 16

        static let panelBackground = Color.black
        static let surface = Color(
            red: 18 / 255.0,
            green: 18 / 255.0,
            blue: 18 / 255.0
        )
        static let meterTrack = Color(
            red: 38 / 255.0,
            green: 38 / 255.0,
            blue: 38 / 255.0
        )
        static let warningSurface = Color(
            red: 38 / 255.0,
            green: 30 / 255.0,
            blue: 11 / 255.0
        )
        static let primaryText = Color.white
        static let secondaryText = Color(
            red: 138 / 255.0,
            green: 138 / 255.0,
            blue: 138 / 255.0
        )
        static let inactiveTabText = Color(
            red: 218 / 255.0,
            green: 218 / 255.0,
            blue: 218 / 255.0
        )
        static let counterText = Color(
            red: 135 / 255.0,
            green: 135 / 255.0,
            blue: 135 / 255.0
        )
        static let danger = Color(
            red: 254 / 255.0,
            green: 75 / 255.0,
            blue: 75 / 255.0
        )
        static let warning = Color(
            red: 254 / 255.0,
            green: 200 / 255.0,
            blue: 75 / 255.0
        )
        static let cyan = Color(
            red: 20 / 255.0,
            green: 212 / 255.0,
            blue: 255 / 255.0
        )
        static let success = Color(
            red: 20 / 255.0,
            green: 255 / 255.0,
            blue: 43 / 255.0
        )

        static let tabFont = Font.system(size: 14, weight: .medium)
        static let sectionTitleFont = Font.system(size: 20, weight: .medium)
        static let rowTitleFont = Font.system(size: 14, weight: .medium)
        static let bodyFont = Font.system(size: 14, weight: .regular)
        static let smallFont = Font.system(size: 12, weight: .regular)
        static let smallMediumFont = Font.system(size: 12, weight: .medium)
    }
}

enum MeetingNotchPanelAppearance {
    static func colorScheme(
        inherited: ColorScheme,
        hasPhysicalNotch: Bool
    ) -> ColorScheme {
        _ = inherited
        _ = hasPhysicalNotch
        return .dark
    }
}

private struct MeetingNotchPanelAppearanceModifier: ViewModifier {
    let hasPhysicalNotch: Bool

    func body(content: Content) -> some View {
        content.transformEnvironment(\.colorScheme) { inherited in
            inherited = MeetingNotchPanelAppearance.colorScheme(
                inherited: inherited,
                hasPhysicalNotch: hasPhysicalNotch
            )
        }
    }
}

extension View {
    func meetingNotchPanelAppearance(hasPhysicalNotch: Bool) -> some View {
        modifier(MeetingNotchPanelAppearanceModifier(hasPhysicalNotch: hasPhysicalNotch))
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
                    : Color.primary.opacity(configuration.isPressed ? 0.09 : 0.045),
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
