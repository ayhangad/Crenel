import SwiftUI

/// Dictation: the key you hold, what it typed (copy any line), and the words it should know.
struct DesktopDictationPage: View {
    let actions: DesktopActions
    @ObservedObject var preferences: DesktopPreferencesModel
    let openSettings: (SettingsCategory) -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    @State private var hoveredEntry: AnyHashable?
    @State private var copiedEntry: UUID?
    @State private var newTerm = ""
    @FocusState private var termFocused: Bool
    @Namespace private var recentSpace

    private var trigger: DictationTriggerSettings { preferences.preferences.dictationTrigger }
    private var isToggle: Bool { trigger.mode == .toggle }

    var body: some View {
        DesktopClock { now in
            VStack(spacing: 0) {
                DesktopToolbar(title: "Dictation", meta: toolbarMeta) {
                    HudButton("Shortcut and language", glyph: .sliders, size: .small) { openSettings(.dictation) }
                }
                ScrollView {
                    VStack(spacing: 16) {
                        hero(now: now).desktopEnter(0)
                        HStack(alignment: .top, spacing: 16) {
                            recent(now: now)
                            words.frame(width: 300)
                        }
                        .desktopEnter(1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
        .task(id: copiedEntry) {
            guard copiedEntry != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            copiedEntry = nil
        }
    }

    private var toolbarMeta: String {
        if !preferences.preferences.dictationEnabled { return "Off" }
        return isToggle ? "Press \(preferences.keyPhrase), speak, press again" : "Hold \(preferences.keyPhrase), speak, let go"
    }

    // MARK: Hero

    private func hero(now: Date) -> some View {
        let today = DesktopStats.dictationToday(appState.dictationHistory, now: now)
        return VStack(spacing: 16) {
            HStack(spacing: 28) {
                HudBigKeycap(preferences.keyLabel, glyph: trigger.trigger == .fnHold ? .globe : .keyboard, lamp: keyLamp)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: isToggle ? "Press \(preferences.keyPhrase) and speak" : "Hold \(preferences.keyPhrase) and speak")
                        .font(Hud.font(20, .semibold)).tracking(-0.28).foregroundStyle(Hud.Ink.ink1)
                    Text(isToggle
                         ? "Words appear under the notch as you talk. Press again and they’re typed where your cursor is."
                         : "Words appear under the notch as you talk. Let go and they’re typed where your cursor is.")
                        .font(Hud.font(13, .regular)).foregroundStyle(Hud.Ink.ink3)
                        .lineSpacing(3)
                        .frame(maxWidth: 400, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        HudAnnunciator(items: [.init(DictationTriggerMode.holdToTalk, "Hold to talk"), .init(DictationTriggerMode.toggle, "Toggle")],
                                       selection: Binding(get: { trigger.mode }, set: { mode in preferences.update { $0.dictationTrigger.mode = mode } }))
                        HStack(spacing: 6) {
                            HudChip(languageTitle, glyph: .globe, style: .tag)
                            HudChip("On this Mac", glyph: .shield, style: .tag)
                            if trigger.allowsDoubleTapHandsFree, trigger.trigger == .fnHold {
                                HudChip("Double-tap for hands-free", style: .tag) { EmptyView() }
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    readout("\(today.words)", "words today")
                    HudWellDivider()
                    readout("\(today.count)", "dictations")
                }
                .padding(.vertical, 14)
                .fixedSize()
                .hudWell()
            }
            if let problem = availabilityProblem {
                HudActions {
                    HudStatusShape(.off)
                    Text(verbatim: problem.message)
                } buttons: {
                    HudButton(problem.button, size: .small, action: problem.action)
                }
                .padding(.leading, 4)
            }
        }
        .padding(24)
        .hudPanel()
    }

    private func readout(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HudSegmentDigits(value, height: 22)
            Text(label).hud(.meta)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private var keyLamp: Hud.LampColor {
        switch appState.dictationAvailability {
        case .ready: .teal
        case .needsInputMonitoring: .amber
        case .disabled: .off
        }
    }

    private var languageTitle: String {
        switch preferences.preferences.dictationLanguage {
        case .automatic: "System language"
        case .turkish: "Turkish"
        case .english: "English"
        }
    }

    private var availabilityProblem: (message: String, button: String, action: () -> Void)? {
        switch appState.dictationAvailability {
        case .ready: nil
        case .needsInputMonitoring:
            ("Input Monitoring is off — Crenel can’t hear the key.", "Allow", crenelActions.dictation.requestInputMonitoring)
        case .disabled:
            preferences.isLoaded && !preferences.preferences.dictationEnabled
                ? ("Dictation is turned off.", "Turn on", { preferences.update { $0.dictationEnabled = true } })
                : nil
        }
    }

    // MARK: Recent

    private func recent(now: Date) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent").hud(.label, Hud.Ink.ink2)
                Spacer(minLength: 4)
                Text("kept on this Mac").hud(.micro).padding(.trailing, 8)
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 36)
            if appState.dictationHistory.isEmpty {
                HStack {
                    Text("Nothing dictated yet").hud(.body, Hud.Ink.ink2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: Hud.Row.twoLine)
            }
            ForEach(appState.dictationHistory.prefix(20)) { entry in
                HStack(alignment: .top, spacing: Hud.Row.gap) {
                    HudTimeColumn(DesktopFormat.clock(entry.createdAt), place(entry))
                    Text(verbatim: entry.finalText)
                        .font(Hud.font(13, .regular)).foregroundStyle(Hud.Ink.ink1)
                        .lineSpacing(3.5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HudIconButton(.copy, framed: true, small: true, tint: copiedEntry == entry.id ? Hud.Ink.ok : nil, help: "Copy") {
                        actions.copyText(entry.finalText)
                        copiedEntry = entry.id
                    }
                }
                .padding(.horizontal, Hud.Row.inset)
                .padding(.vertical, 10)
                .opacity(entry.delivery == nil ? 0.6 : 1)
                .hudGlide(entry.id, hovered: $hoveredEntry, in: recentSpace)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .hudPanel()
    }

    /// Where the words went: the app they were typed into, or the clipboard.
    private func place(_ entry: DictationHistoryEntry) -> String {
        switch entry.delivery {
        case .none: "Copied"
        case .taskCreated: "Tasks"
        default: entry.appName ?? "Typed"
        }
    }

    // MARK: Words to know

    private var words: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Words to know").hud(.label, Hud.Ink.ink1)
                Text("Names and terms it should spell your way.").hud(.meta)
            }
            HStack(spacing: 6) {
                TextField("", text: $newTerm, prompt: Text(verbatim: "Crenel, SwiftUI, Ayhan").foregroundStyle(Hud.Ink.ink3))
                    .textFieldStyle(.plain)
                    .hud(.body)
                    .focused($termFocused)
                    .onSubmit(addTerm)
                    .hudField(height: 30, isFocused: termFocused)
                    .accessibilityLabel("New word")
                Button(action: addTerm) { HudIcon(.plus, size: 12) }
                    .buttonStyle(HudButtonStyle(kind: .iconFramed, size: .small))
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add")
                    .accessibilityLabel("Add word")
            }
            if !preferences.preferences.dictationVocabulary.isEmpty {
                DesktopFlow(spacing: 6) {
                    ForEach(preferences.preferences.dictationVocabulary, id: \.self) { term in
                        Button {
                            preferences.update { $0.dictationVocabulary.removeAll { $0 == term } }
                        } label: {
                            DesktopWordChip(term: term)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                        .accessibilityLabel(Text(verbatim: "Remove \(term)"))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel()
    }

    private func addTerm() {
        let terms = newTerm.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return }
        preferences.update { preferences in
            for term in terms where !preferences.dictationVocabulary.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
                preferences.dictationVocabulary.append(term)
            }
        }
        newTerm = ""
        termFocused = true
    }
}

/// A word chip (`.dchip`): the term and a small × that removes it.
private struct DesktopWordChip: View {
    let term: String
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: term).hud(.meta, Hud.Ink.ink2)
            HudIcon(.close, size: 8).foregroundStyle(isHovering ? Hud.Ink.ink2 : Hud.Ink.ink4)
        }
        .lineLimit(1)
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 1, opacity: isHovering ? 0.09 : 0.06)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Hud.Motion.hover, value: isHovering)
    }
}

/// Wrapping rows of chips.
struct DesktopFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, rows.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (origins, maxWidth, y + rowHeight)
    }
}
