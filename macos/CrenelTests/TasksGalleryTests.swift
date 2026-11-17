import AppKit
import SwiftUI
import XCTest
@testable import Crenel

/// Offscreen renders of every Tasks state of the prototype (`tpl-tasks-body`,
/// `tpl-task-card`, `tpl-tray`) plus checks of the row formatting. PNGs are written to
/// `artifacts/ui-audit/tasks/` when `/tmp/CrenelExportUIAudit` exists, to be
/// compared with `/tmp/proto/<state-id>.png`.
@MainActor
final class TasksGalleryTests: XCTestCase {
    private let calendar = Calendar.current

    func testEveryTasksStateRenders() throws {
        let sample = Sample(now: Date(), calendar: calendar)

        try render("o-tasks", TasksView(), sample.state())
        try render("o-tasks-typing", TasksView(initialInput: "Call mom tomorrow 3pm every week !!!"), sample.state())
        try render("o-tasks-quickpick", TasksView(initialInput: "Buy coffee beans"), sample.state())
        try render("o-tasks-completion", TasksView(initialInput: "Wri"), sample.state())
        try render("o-tasks-actions", TasksView(initiallyRevealedTaskID: sample.reply.id), sample.state())
        try render("o-tasks-card", TasksView(initiallyEditingTaskID: sample.writing.id), sample.state(), height: 860)
        try render("o-tasks-empty", TasksView(), sample.state(tasks: []), height: 200)
        try render("o-tasks-local", TasksView(), sample.state(storage: .localNotConnected))
        try render("o-tasks-finished", TasksView(initiallyShowsHistory: true), sample.state(), height: 300)
        try render("o-tasks-finished-empty", TasksView(initiallyShowsHistory: true), sample.state(tasks: []), height: 160)
        // The alerts (`a-delete-task`, `a-clear-history`) and the context menu (`menu-task`)
        // are native AppKit surfaces; they are not rendered here.
    }

    func testRowDueLabelsAreCompact() {
        let now = date(2026, 11, 17, 10, 42)
        func due(_ day: Int, hour: Int? = nil) -> (text: String, isClock: Bool)? {
            let base = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now))!
            let date = hour.map { calendar.date(byAdding: .hour, value: $0, to: base)! } ?? base
            return TaskRowFormat.due(for: TaskItem(title: "t", dueDate: date, dueHasTime: hour != nil), now: now, calendar: calendar)
        }
        XCTAssertNil(due(0))
        XCTAssertEqual(due(0, hour: 15)?.text, "15:00")
        XCTAssertEqual(due(0, hour: 15)?.isClock, true)
        XCTAssertEqual(due(-1)?.text, "Yesterday")
        XCTAssertEqual(due(1)?.text, "Wed")
        XCTAssertEqual(due(6)?.text, "Mon")
        XCTAssertEqual(due(7)?.text, "Tue 24")
        XCTAssertEqual(due(60)?.text, "16 Jan 2027")
        XCTAssertNil(TaskRowFormat.due(for: TaskItem(title: "t"), now: now, calendar: calendar))
    }

    func testTimeOnTaskAndFinishedTitles() {
        let now = date(2026, 11, 17, 10, 42)
        XCTAssertEqual(TaskRowFormat.spent(since: now.addingTimeInterval(-25 * 60), now: now).digits, "25")
        XCTAssertEqual(TaskRowFormat.spent(since: now.addingTimeInterval(-25 * 60), now: now).unit, "min")
        XCTAssertEqual(TaskRowFormat.spent(since: now.addingTimeInterval(-125 * 60), now: now).digits, "2:05")
        XCTAssertEqual(TaskRowFormat.spent(since: now.addingTimeInterval(60), now: now).digits, "0")
        XCTAssertEqual(TaskRowFormat.historyTitle(for: now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(TaskRowFormat.historyTitle(for: now.addingTimeInterval(-86_400), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(TaskRowFormat.historyTitle(for: date(2026, 11, 13, 9, 0), now: now, calendar: calendar), "Fri 13")
        XCTAssertEqual(TaskStatus.allCases.map(\.shortTitle), ["To do", "Doing", "Blocked", "Done"])
    }

    // MARK: Sample data (the prototype's list)

    private struct Sample {
        let now: Date
        let calendar: Calendar
        let meetingID = UUID()
        let writing: TaskItem
        let reply: TaskItem
        let tasks: [TaskItem]

        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
            let today = calendar.startOfDay(for: now)
            func day(_ offset: Int, hour: Int = 0, minute: Int = 0) -> Date {
                calendar.date(byAdding: DateComponents(day: offset, hour: hour, minute: minute), to: today)!
            }
            writing = TaskItem(title: "Write release notes", status: .inProgress, startedAt: now.addingTimeInterval(-25 * 60),
                               dueDate: day(0, hour: 23, minute: 30), dueHasTime: true, recurrence: .weekly, priority: .medium,
                               sourceMeetingID: meetingID)
            reply = TaskItem(title: "Reply to Deniz about pricing", dueDate: day(-1), priority: .high)
            tasks = [
                writing,
                TaskItem(title: "Ship notarized build", status: .blocked, sourceMeetingID: meetingID),
                reply,
                TaskItem(title: "Call the bank", dueDate: day(0, hour: 23, minute: 45), dueHasTime: true),
                TaskItem(title: "Water the plants", dueDate: day(1), recurrence: .weekly),
                TaskItem(title: "Plan Q1 roadmap", dueDate: day(8), priority: .medium),
                TaskItem(title: "Read “Shape Up”"),
                TaskItem(title: "Book flights", status: .completed, completedAt: now),
                TaskItem(title: "Send invoice", status: .completed, completedAt: day(-1, hour: 17, minute: 40)),
                TaskItem(title: "Renew domain", status: .completed, completedAt: day(-1, hour: 11, minute: 5))
            ]
        }

        @MainActor
        func state(tasks: [TaskItem]? = nil, storage: TaskStorageStatus = .reminders(listTitle: "Crenel")) -> AppState {
            let state = AppState()
            state.replaceTasks(tasks ?? self.tasks)
            state.updateTaskStorageStatus(storage)
            state.replaceStoredMeetings([
                StoredMeeting(id: meetingID, title: "Design review", startedAt: now.addingTimeInterval(-7200),
                              endedAt: now.addingTimeInterval(-3600), sourceMeeting: nil, audioFileName: "fixture.m4a",
                              processingStatus: .completed)
            ])
            return state
        }
    }

    // MARK: Rendering

    /// The open notch's content column: 560 pt panel, 14 pt inset on each side.
    private func render(_ name: String, _ view: TasksView, _ state: AppState, height: CGFloat = 580) throws {
        let content = view
            .environmentObject(state)
            .padding(.horizontal, Hud.Notch.openInset)
            .padding(.vertical, 8)
            .frame(width: Hud.Notch.openWidth, height: height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let size = CGSize(width: Hud.Notch.openWidth, height: height)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), "\(name) did not render")
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertGreaterThan(litPixels(in: bitmap), 200, "\(name) rendered nothing")
        guard FileManager.default.fileExists(atPath: "/tmp/CrenelExportUIAudit") else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appending(path: "artifacts/ui-audit/tasks/\(name).png")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
    }

    private func litPixels(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                if let color = bitmap.colorAt(x: x, y: y), color.brightnessComponent > 0.3 { count += 1 }
            }
        }
        return count
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
