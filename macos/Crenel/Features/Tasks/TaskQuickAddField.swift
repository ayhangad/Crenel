import SwiftUI

/// Type and press Return. While typing, dates, repeats and priority are recognised live
/// and shown under the field as lamp chips; Return saves the task with them. A title
/// used before is completed inline as ghost text (Tab accepts). When nothing is
/// recognised yet, quick picks offer the common values. Clicking a recognised value
/// drops it.
struct TaskQuickAddField: View {
    var knownTitles: [String]
    let onSubmit: (TaskInputParseResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var text: String
    /// Recognised values the user dismissed for the current text.
    @State private var dismissed: Set<String> = []
    private let parser = TaskInputParser()

    init(knownTitles: [String] = [], initialText: String = "", onSubmit: @escaping (TaskInputParseResult) -> Void) {
        self.knownTitles = knownTitles
        self.onSubmit = onSubmit
        _text = State(initialValue: initialText)
    }

    var body: some View {
        let suggestions = currentSuggestions
        let hasText = !text.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Hud.Row.gap) {
                HudIcon(.plus, size: 14)
                    .foregroundStyle(focused || !text.isEmpty ? Hud.Ink.ink1 : Hud.Ink.ink3)
                ZStack(alignment: .leading) {
                    // Ghost completion sits behind the field, aligned to the typed text.
                    if let completion {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(Text(text).foregroundColor(.clear))\(Text(completion).foregroundColor(Hud.Ink.ink4))")
                                .font(Hud.Style.body.font)
                            Text("tab").hud(.micro, Hud.Ink.ink4)
                        }
                        .lineLimit(1)
                        .accessibilityHidden(true)
                    }
                    TextField("", text: $text, prompt: Text("Add a task, like “call mom tomorrow 3pm”").foregroundColor(Hud.Ink.ink3))
                        .textFieldStyle(.plain)
                        .font(Hud.Style.body.font)
                        .foregroundStyle(Hud.Ink.ink1)
                        .focused($focused)
                        .onSubmit(submit)
                        .onKeyPress(.tab) {
                            guard let completion else { return .ignored }
                            text += completion
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            guard !text.isEmpty else { return .ignored }
                            reset()
                            return .handled
                        }
                        .accessibilityLabel("New task")
                        .accessibilityHint("Dates like tomorrow 3pm are recognised. Press Return to add.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "↩")
                    .hud(.micro, focused ? Hud.Ink.ink3 : Hud.Ink.ink4)
                    .accessibilityHidden(true)
            }
            .hudField(height: 44, radius: 12, isFocused: focused, padding: Hud.Row.inset)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .onChange(of: text) { _, newValue in
                if newValue.isEmpty { dismissed = [] }
            }

            // Below the field: what was recognised, or quick picks while nothing is.
            if hasText {
                HStack(spacing: 4) {
                    if suggestions.isEmpty {
                        ForEach(QuickPick.allCases, id: \.self) { pick in
                            Button {
                                text = text.trimmingCharacters(in: .whitespaces) + " " + pick.token
                                focused = true
                            } label: {
                                HudChip(pick.title, glyph: .plus, style: .outline)
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    } else {
                        ForEach(suggestions) { suggestion in
                            Button {
                                dismissed.insert(suggestion.matchedText)
                                focused = true
                            } label: {
                                TaskValueChip(label: label(for: suggestion), kind: suggestion.kind)
                            }
                            .buttonStyle(.plain)
                            .help("Click to drop")
                            .accessibilityLabel("Recognised: \(label(for: suggestion)). Remove")
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(reduceMotion ? nil : Hud.Motion.slab, value: suggestions.map(\.id))
        .animation(reduceMotion ? nil : Hud.Motion.slab, value: hasText)
    }

    private enum QuickPick: CaseIterable {
        case today, tomorrow, priority

        var token: String {
            switch self {
            case .today: "today"
            case .tomorrow: "tomorrow"
            case .priority: "!!!"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .priority: "High priority"
            }
        }
    }

    private var currentSuggestions: [TaskInputSuggestion] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return parser.suggestions(for: text, now: Date())
            .filter { !dismissed.contains($0.matchedText) }
    }

    /// Inline completion from titles used before.
    private var completion: String? {
        guard text.count >= 2 else { return nil }
        let lower = text.lowercased()
        return knownTitles.first { $0.lowercased().hasPrefix(lower) && $0.count > text.count }
            .map { String($0.dropFirst(text.count)) }
    }

    private func label(for suggestion: TaskInputSuggestion) -> String {
        switch suggestion.kind {
        case .due(let date, let hasTime): TaskDueFormatter.label(due: date, hasTime: hasTime, now: Date())
        case .recurrence(let recurrence): recurrence.displayText
        case .priority(let priority): priority.shortText
        }
    }

    private func submit() {
        let result = parser.apply(currentSuggestions, to: text)
        guard let title = TaskItem.normalizedTitle(result.title) else { return }
        var final = result
        final.title = title
        onSubmit(final)
        reset()
        focused = true
    }

    private func reset() {
        text = ""
        dismissed = []
    }
}

/// A recognised value under the input (`.chip`): a lamp (amber for a date, white for a
/// repeat) or priority bars, the value, and a small cross — clicking drops the value.
private struct TaskValueChip: View {
    let label: String
    let kind: TaskInputSuggestion.Kind
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .due: HudLamp(.amber)
            case .recurrence: HudLamp(.white)
            case .priority(let priority):
                HudPriorityBars(level: priority.barLevel, tint: priority == .high ? Hud.Ink.signal : Hud.Ink.ink2)
            }
            Text(label).hud(.meta, Hud.Ink.ink2)
            HudIcon(.close, size: 8).foregroundStyle(Hud.Ink.ink4).padding(.leading, 2)
        }
        .lineLimit(1)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(white: 1, opacity: isHovering ? 0.09 : 0.06)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Hud.Motion.hover, value: isHovering)
    }
}

extension TaskPriority {
    /// One-word label for chips and the priority control.
    var shortText: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Lit bars of the priority mark (`.pri`).
    var barLevel: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }
}
