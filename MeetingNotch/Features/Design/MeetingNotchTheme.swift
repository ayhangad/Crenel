import SwiftUI

private struct WorkspacePaletteKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var workspacePalette: Bool {
        get { self[WorkspacePaletteKey.self] }
        set { self[WorkspacePaletteKey.self] = newValue }
    }
}

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
    static let workspaceBackground = Color(white: 23 / 255.0)
    static let sidebarBackground = Color(white: 19 / 255.0)
    static let pageTitleFont = Font.system(size: 26, weight: .semibold)

    // Workspace surfaces are softer than the physical notch palette.
    static let panelBackground = MainPanel.panelBackground
    static let surface = Color(white: 32 / 255.0)
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
    static let primaryText = Color(white: 0.90)
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

        static let tabHeight: CGFloat = 40
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
            red: 163 / 255.0,
            green: 163 / 255.0,
            blue: 163 / 255.0
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
            red: 95 / 255.0,
            green: 216 / 255.0,
            blue: 151 / 255.0
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
            .meetingControlFeedback()
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
    @Environment(\.workspacePalette) private var workspacePalette

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
            .meetingControlFeedback()
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
        case .primary: workspacePalette ? Color(white: 0.82) : MeetingNotchTheme.primaryText
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

// A single motion vocabulary for every surface. No repeating decorative animation:
// playback clocks and capture meters only move when their underlying value changes.
enum MeetingNotchMotion {
    static func interaction(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.14)
    }

    static func navigation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.24, extraBounce: 0)
    }

    static func content(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(y: -3))
        )
    }
}

private struct MeetingControlFeedback: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var radius: CGFloat
    var restingBorder: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(hovering && isEnabled ? 0.055 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isFocused ? MeetingNotchTheme.cyan
                        : Color.white.opacity(contrast == .increased ? 0.45 : (hovering ? 0.14 : (restingBorder ? 0.06 : 0))),
                        lineWidth: isFocused ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .onHover { hovering = $0 }
            .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: hovering)
    }
}

private struct MeetingFieldSurface: ViewModifier {
    let focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(MeetingNotchTheme.bodyFont)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(MeetingNotchTheme.elevatedSurface.opacity(0.6),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? MeetingNotchTheme.cyan : Color.white.opacity(contrast == .increased ? 0.4 : 0.1),
                        lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .animation(MeetingNotchMotion.interaction(reduceMotion: reduceMotion), value: focused)
    }
}

extension View {
    func meetingControlFeedback(radius: CGFloat = MeetingNotchTheme.controlRadius, restingBorder: Bool = true) -> some View {
        modifier(MeetingControlFeedback(radius: radius, restingBorder: restingBorder))
    }

    func meetingFieldSurface(focused: Bool = false) -> some View {
        modifier(MeetingFieldSurface(focused: focused))
    }
}

struct MeetingNotchRowButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(selected ? Color.white.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .meetingControlFeedback(radius: 12, restingBorder: selected)
    }
}

struct MeetingNotchEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 12 : 20) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 22 : 28, weight: .light))
                .foregroundStyle(MeetingNotchTheme.secondaryText)
                .frame(width: compact ? 48 : 64, height: compact ? 48 : 64)
                .background(MeetingNotchTheme.surface, in: RoundedRectangle(cornerRadius: compact ? 16 : 22))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title)
                    .font(compact ? MeetingNotchTheme.rowTitleFont : .system(size: 22, weight: .medium))
                    .foregroundStyle(MeetingNotchTheme.primaryText)
                if !detail.isEmpty {
                    Text(detail).font(MeetingNotchTheme.bodyFont)
                        .foregroundStyle(MeetingNotchTheme.secondaryText).lineSpacing(3)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: compact ? 300 : 380)
        .padding(compact ? 16 : 28)
    }
}

struct MeetingNotchFeedback: View {
    let message: String
    var isFailure = false
    var body: some View {
        Label(message, systemImage: isFailure ? "exclamationmark.circle" : "checkmark.circle")
            .font(MeetingNotchTheme.metadataFont)
            .foregroundStyle(isFailure ? MeetingNotchTheme.warning : MeetingNotchTheme.success)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isFailure ? MeetingNotchTheme.warning : MeetingNotchTheme.success).opacity(0.07),
                in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
}

struct MeetingNotchActionGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}
