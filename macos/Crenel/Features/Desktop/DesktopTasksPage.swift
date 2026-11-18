import SwiftUI

/// Tasks: the shared list, and a rail with the day as a gauge, what is due, and where
/// the list syncs.
struct DesktopTasksPage: View {
    let actions: DesktopActions
    let openSettings: (SettingsCategory) -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.crenelActions) private var crenelActions
    @Environment(\.desktopFixedNow) private var fixedNow

    var body: some View {
        DesktopClock { now in
            let presentation = appState.taskPresentation(now: now)
            let done = presentation.sections.first { $0.kind == .completedToday }?.tasks.count ?? 0
            VStack(spacing: 0) {
                DesktopToolbar(title: "Tasks", meta: meta(open: presentation.activeCount, done: done)) {
                    if appState.taskStorageStatus.isReminders {
                        HudButton("Open in Reminders", glyph: .link, size: .small, action: actions.openReminders)
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    ScrollView {
                        TasksView()
                            .frame(maxWidth: 620, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.never)
                    VStack(spacing: 16) {
                        dayGauge(presentation, done: done, now: now).desktopEnter(0)
                        duePanel(presentation, now: now).desktopEnter(1)
                        storagePanel.desktopEnter(2)
                    }
                    .frame(width: 268)
                    .padding(.bottom, 24)
                }
                .padding(.leading, 20)
                .padding(.trailing, 24)
            }
        }
    }

    private func meta(open: Int, done: Int) -> String {
        done > 0 ? "\(open) open · \(done) done today" : "\(open) open"
    }

    // MARK: The day

    private func dayGauge(_ presentation: TaskListPresentation, done: Int, now: Date) -> some View {
        let total = done + presentation.activeCount
        return VStack(spacing: 16) {
            HudGauge(value: total > 0 ? Double(done) / Double(total) : 0, ticks: 40, major: 8, size: 128, tint: Hud.Ink.ok, ignite: fixedNow == nil) {
                HudSegmentDigits("\(done)", height: 30)
                Text(verbatim: "of \(total) done").hud(.micro, Hud.Ink.ink3)
            }
            .frame(width: 128, height: 128)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(done) of \(total) done today"))
            Text(verbatim: sentence(presentation, total: total, now: now))
                .hud(.meta)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .hudPanel()
    }

    private func sentence(_ presentation: TaskListPresentation, total: Int, now: Date) -> String {
        if let task = presentation.inProgress {
            let minutes = max(0, Int(now.timeIntervalSince(task.startedAt ?? now) / 60))
            return "“\(task.title)” is the one in progress: \(DesktopFormat.minutes(TimeInterval(minutes * 60))) so far."
        }
        if total == 0 { return "Nothing on the list yet." }
        if presentation.activeCount == 0 { return "Everything on today’s list is done." }
        return "Nothing is in progress right now."
    }

    // MARK: Due

    private func duePanel(_ presentation: TaskListPresentation, now: Date) -> some View {
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let due = appState.tasks
            .filter { $0.isActive && ($0.dueDate.map { $0 < endOfDay } ?? false) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let nextTimed = due.first { $0.dueHasTime && ($0.dueDate ?? now) >= now }?.id
        return VStack(spacing: 0) {
            HStack {
                Text("Due").hud(.label, Hud.Ink.ink2)
                Spacer(minLength: 4)
                Text("today").hud(.micro)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            if due.isEmpty {
                HStack(spacing: 12) {
                    HudLamp(.off)
                    Text("Nothing due today").hud(.label, Hud.Ink.ink3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
            }
            ForEach(due.prefix(6)) { task in
                let overdue = isOverdue(task, now: now, calendar: calendar)
                HStack(spacing: 12) {
                    if overdue {
                        HudStatusShape(.warn, tint: Hud.Ink.live).help("Overdue")
                    } else {
                        HudLamp(task.id == nextTimed ? .white : .off)
                    }
                    Text(verbatim: task.title).hud(.label, overdue || task.id == nextTimed ? Hud.Ink.ink1 : Hud.Ink.ink2)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    if overdue {
                        Text("overdue").hud(.meta, Hud.Ink.live)
                    } else if task.dueHasTime, let date = task.dueDate {
                        HudSegmentDigits(DesktopFormat.clock(date), height: 10, color: task.id == nextTimed ? Hud.Ink.ink2 : Hud.Ink.ink3, glows: false)
                    } else {
                        Text("today").hud(.meta)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .hudPanel()
    }

    private func isOverdue(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        guard let due = task.dueDate else { return false }
        return task.dueHasTime ? due < now : due < calendar.startOfDay(for: now)
    }

    // MARK: Where it syncs

    @ViewBuilder private var storagePanel: some View {
        HStack(spacing: 12) {
            switch appState.taskStorageStatus {
            case .reminders(let listTitle):
                HudLamp(.teal)
                storageText("Apple Reminders", "“\(listTitle)” list · synced")
            case .localNotConnected:
                HudLamp(.off)
                storageText("On this Mac only", "Reminders isn’t connected")
                HudButton("Connect", size: .mini, action: crenelActions.tasks.connectReminders)
            case .localDenied:
                HudStatusShape(.off)
                storageText("On this Mac only", "Reminders access is off")
                HudButton("Settings", size: .mini) { openSettings(.tasks) }
            case .localByChoice:
                HudLamp(.off)
                storageText("On this Mac only", "Kept in a local file")
            case .localAfterError(let message):
                HudStatusShape(.err)
                storageText("On this Mac only", message)
                HudButton("Settings", size: .mini) { openSettings(.tasks) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel()
    }

    private func storageText(_ title: LocalizedStringKey, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).hud(.label, Hud.Ink.ink1)
            Text(verbatim: detail).hud(.meta).lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
