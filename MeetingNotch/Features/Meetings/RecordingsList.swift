import SwiftUI

// MARK: - History

/// Recorded meetings, newest first. Time on the left of the second line, duration on the
/// right; state is shown only when it needs attention.
struct RecentMeetingsList: View {
    let meetings: [StoredMeeting]
    let onOpen: (StoredMeeting) -> Void
    let onDelete: (StoredMeeting) -> Void
    let onRetry: (StoredMeeting) -> Void
    @State private var hovered: AnyHashable?
    @Namespace private var glide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if meetings.isEmpty {
                HStack(spacing: Hud.Space.x3) {
                    HudIcon(.history).foregroundStyle(Hud.Ink.text3)
                    Text("No recordings yet").hud(.body, Hud.Ink.text2)
                }
                .padding(.horizontal, Hud.Size.rowInset)
                .frame(height: Hud.Size.row)
            }
            ForEach(groups, id: \.title) { group in
                HudGroupHeader(title: LocalizedStringKey(group.title))
                    .padding(.top, group.title == groups.first?.title ? 0 : Hud.Space.x3)
                ForEach(group.meetings) { meeting in
                    row(meeting)
                        .hudGlide(meeting.id, hovered: $hovered, in: glide)
                }
            }
        }
    }

    private var groups: [(title: String, meetings: [StoredMeeting])] {
        var result: [(title: String, meetings: [StoredMeeting])] = []
        for meeting in meetings {
            let title = HudFormat.day(meeting.startedAt, now: Date())
            if result.last?.title == title {
                result[result.count - 1].meetings.append(meeting)
            } else {
                result.append((title, [meeting]))
            }
        }
        return result
    }

    private func row(_ meeting: StoredMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Hud.Space.x3) {
                Text(meeting.title).hud(.body).lineLimit(1)
                Spacer(minLength: Hud.Space.x2)
                Text(HudFormat.clock(meeting.startedAt)).hud(.value, Hud.Ink.text2).fixedSize()
            }
            HStack(spacing: Hud.Space.x2) {
                Text(state(meeting) ?? "").hud(.meta, stateColor(meeting)).lineLimit(1)
                Spacer(minLength: Hud.Space.x2)
                Text(HudFormat.elapsed(meeting.duration)).hud(.meta, Hud.Ink.text3).fixedSize()
            }
        }
        .padding(.horizontal, Hud.Size.rowInset)
        .frame(height: Hud.Size.row)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(meeting) }
        .contextMenu {
            Button("Open meeting") { onOpen(meeting) }
            if meeting.processingStatus == .failed {
                Button("Retry processing") { onRetry(meeting) }
            }
            Divider()
            Button("Delete meeting", role: .destructive) { onDelete(meeting) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(meeting.title), \(state(meeting) ?? ""), \(HudFormat.elapsed(meeting.duration))")
    }

    private func state(_ meeting: StoredMeeting) -> String? {
        if meeting.summaryNeedsAttention == true { return String(localized: "Summary pending") }
        switch meeting.processingStatus {
        case .processing: return String(localized: "Processing")
        case .failed: return String(localized: "Failed")
        case .recorded: return String(localized: "Not transcribed")
        case .completed: return nil
        }
    }

    private func stateColor(_ meeting: StoredMeeting) -> Color {
        if meeting.processingStatus == .failed { return Hud.Ink.live }
        if meeting.summaryNeedsAttention == true { return Hud.Ink.signal }
        return Hud.Ink.text3
    }
}
