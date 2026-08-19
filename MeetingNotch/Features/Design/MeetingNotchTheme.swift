import SwiftUI

enum MeetingNotchTheme {
    static let panelWidth: CGFloat = 600
    static let detailPanelWidth: CGFloat = panelWidth
    static let panelMinimumWidth: CGFloat = 320
    static let panelHorizontalPadding: CGFloat = 12
    static let panelVerticalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let contentSpacing: CGFloat = 12
    static let itemSpacing: CGFloat = 10
    static let surfaceRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let controlHeight: CGFloat = 40
    static let tabHeight: CGFloat = 40
    static let tabBarPadding: CGFloat = 4
    static let iconSize: CGFloat = 20

    // The full application uses the same explicit dark palette as the four Figma panels.
    static let panelBackground = MainPanel.panelBackground
    static let surface = MainPanel.surface
    static let surfaceHover = Color(
        red: 28 / 255.0,
        green: 28 / 255.0,
        blue: 28 / 255.0
    )
    static let elevatedSurface = MainPanel.meterTrack
    static let hairline = MainPanel.meterTrack
    static let subtleHairline = MainPanel.meterTrack.opacity(0.8)

    static let inactiveTabForegroundOpacity = 0.68
    static let inactiveTabHoverForegroundOpacity = 0.88
    static let activeTabFillOpacity = 0.11

    static let inactiveTabForeground = MainPanel.inactiveTabText
    static let inactiveTabHoverForeground = MainPanel.primaryText
    static let activeTabForeground = MainPanel.primaryText
    static let activeTabFill = MainPanel.surface
    static let tabTrackFill = MainPanel.panelBackground

    static let accent = MainPanel.cyan
    static let cyan = MainPanel.cyan
    static let success = MainPanel.success
    static let warning = MainPanel.warning
    static let danger = MainPanel.danger
    static let primaryText = MainPanel.primaryText
    static let secondaryText = MainPanel.secondaryText

    static var titleFont: Font {
        MainPanel.sectionTitleFont
    }

    static var sectionTitleFont: Font {
        MainPanel.rowTitleFont
    }

    static var rowTitleFont: Font {
        MainPanel.rowTitleFont
    }

    static var bodyFont: Font {
        MainPanel.bodyFont
    }

    static var metadataFont: Font {
        MainPanel.smallFont.monospacedDigit()
    }

    static var dataFont: Font {
        MainPanel.smallMediumFont.monospacedDigit()
    }

    static var controlFont: Font {
        MainPanel.smallMediumFont
    }

    enum MainPanel {
        static let horizontalPadding: CGFloat = 12
        static let listRowHorizontalInset: CGFloat = 8
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
            .font(.system(size: MeetingNotchTheme.MainPanel.smallIconSize, weight: .semibold))
            .foregroundStyle(isActive ? tint : tint.opacity(0.82))
            .frame(
                width: MeetingNotchTheme.controlHeight,
                height: MeetingNotchTheme.controlHeight
            )
            .contentShape(Rectangle())
            .background(
                isActive
                    ? tint.opacity(0.14)
                    : configuration.isPressed
                        ? MeetingNotchTheme.surfaceHover
                        : MeetingNotchTheme.surface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
            )
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct MeetingNotchActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case danger
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MeetingNotchTheme.controlFont)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: MeetingNotchTheme.controlHeight)
            .contentShape(Rectangle())
            .background(
                background.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.controlRadius,
                    style: .continuous
                )
            )
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .secondary: MeetingNotchTheme.primaryText
        case .danger: MeetingNotchTheme.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: MeetingNotchTheme.primaryText
        case .secondary: MeetingNotchTheme.surface
        case .danger: MeetingNotchTheme.danger.opacity(0.12)
        }
    }
}

struct MeetingNotchStatusBadge: View {
    let title: String
    let assetName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(
                    width: MeetingNotchTheme.MainPanel.smallIconSize,
                    height: MeetingNotchTheme.MainPanel.smallIconSize
                )
            Text(title)
                .font(MeetingNotchTheme.MainPanel.smallMediumFont)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(
                cornerRadius: MeetingNotchTheme.controlRadius,
                style: .continuous
            )
        )
    }
}

struct MeetingNotchCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MeetingNotchTheme.surface,
                in: RoundedRectangle(
                    cornerRadius: MeetingNotchTheme.surfaceRadius,
                    style: .continuous
                )
            )
    }
}
