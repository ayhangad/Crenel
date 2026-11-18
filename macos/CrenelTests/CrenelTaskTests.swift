import XCTest
@testable import Crenel

final class CrenelTaskTests: XCTestCase {
    // Monday 16 Nov 2026 10:00 Istanbul.
    private let now = Date(timeIntervalSince1970: 1_794_812_400)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: Presentation

    func testSectionsFollowStateAndDueDate() {
        let startOfToday = calendar.startOfDay(for: now)
        let overdue = TaskItem(title: "Dün", dueDate: startOfToday.addingTimeInterval(-86_400))
        let overdueTimed = TaskItem(title: "Saat geçti", dueDate: now.addingTimeInterval(-600), dueHasTime: true)
        let today = TaskItem(title: "Bugün", dueDate: startOfToday)
        let upcoming = TaskItem(title: "Yarın", dueDate: startOfToday.addingTimeInterval(86_400))
        let someday = TaskItem(title: "Tarihsiz")
        let working = TaskItem(title: "Çalışılıyor", status: .inProgress)
        var doneToday = TaskItem(title: "Bitti")
        doneToday.setStatus(.completed, at: now.addingTimeInterval(-60))
        var doneYesterday = TaskItem(title: "Dün bitti")
        doneYesterday.setStatus(.completed, at: now.addingTimeInterval(-86_400))

        let presentation = TaskListPresentation(
            tasks: [someday, upcoming, today, overdue, overdueTimed, working, doneToday, doneYesterday],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(presentation.sections.map(\.kind), [.inProgress, .overdue, .today, .upcoming, .someday, .completedToday])
        XCTAssertEqual(Set(presentation.sections[1].tasks.map(\.title)), ["Dün", "Saat geçti"])
        XCTAssertEqual(presentation.history.flatMap(\.tasks).map(\.title), ["Dün bitti"])
        XCTAssertEqual(presentation.activeCount, 6)
        XCTAssertEqual(presentation.inProgress?.title, "Çalışılıyor")
    }

    func testBlockedTasksGetTheirOwnSectionAfterInProgress() {
        let working = TaskItem(title: "Devam", status: .inProgress)
        let blocked = TaskItem(title: "Bekliyor", status: .blocked, dueDate: now)
        let todo = TaskItem(title: "Sıradaki")

        let presentation = TaskListPresentation(tasks: [todo, blocked, working], now: now, calendar: calendar)

        XCTAssertEqual(presentation.sections.map(\.kind), [.inProgress, .blocked, .someday])
        XCTAssertEqual(presentation.activeCount, 3)
    }

    func testBlockedStateClearsStartAndCompletionDates() {
        var task = TaskItem(title: "API anahtarı bekleniyor")
        task.setStatus(.inProgress, at: now)
        task.setStatus(.blocked, at: now)
        XCTAssertEqual(task.status, .blocked)
        XCTAssertNil(task.startedAt)
        XCTAssertNil(task.completedAt)
        XCTAssertTrue(task.isActive)

        let decoded = try? JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(decoded?.status, .blocked)
    }

    func testBlockedStateRoundTripsThroughRemindersSidecar() throws {
        let task = TaskItem(title: "Onay bekliyor", createdAt: now, status: .blocked)
        let record = ReminderTaskMapper.record(from: task, identifier: "rem-1", calendar: calendar)
        let sidecar = ReminderTaskMapper.sidecar(from: task)
        XCTAssertTrue(sidecar.isBlocked)
        XCTAssertFalse(record.isCompleted)

        let restored = ReminderTaskMapper.task(from: record, sidecar: sidecar, calendar: calendar)
        XCTAssertEqual(restored.status, .blocked)
        XCTAssertEqual(restored.id, task.id)
    }

    func testBlockedReasonRoundTripsThroughRemindersSidecar() throws {
        let task = TaskItem(title: "Ship notarized build", createdAt: now, status: .blocked, blockedReason: "  waiting on QA ")
        XCTAssertEqual(task.blockedReason, "waiting on QA")
        let record = ReminderTaskMapper.record(from: task, identifier: "rem-2", calendar: calendar)
        let sidecar = ReminderTaskMapper.sidecar(from: task)
        XCTAssertEqual(sidecar.blockedReason, "waiting on QA")
        // The reminder itself stays a plain reminder: the reason is not written into its notes.
        XCTAssertNil(record.notes)

        let encoded = try JSONEncoder().encode(sidecar)
        let decodedSidecar = try JSONDecoder().decode(TaskSidecarEntry.self, from: encoded)
        let restored = ReminderTaskMapper.task(from: record, sidecar: decodedSidecar, calendar: calendar)
        XCTAssertEqual(restored.status, .blocked)
        XCTAssertEqual(restored.blockedReason, "waiting on QA")
    }

    func testBlockedReasonIsDroppedWhenTheSidecarIsNoLongerBlocked() {
        let task = TaskItem(title: "Onay", createdAt: now, status: .blocked, blockedReason: "Deniz")
        var record = ReminderTaskMapper.record(from: task, identifier: "rem-3", calendar: calendar)
        record.isCompleted = true
        let restored = ReminderTaskMapper.task(from: record, sidecar: ReminderTaskMapper.sidecar(from: task), calendar: calendar)
        XCTAssertEqual(restored.status, .completed)
        XCTAssertNil(restored.blockedReason)
    }

    func testBlockedReasonClearsWhenStatusLeavesBlocked() throws {
        var task = TaskItem(title: "Sözleşme", status: .blocked)
        task.setBlockedReason("waiting on legal")
        XCTAssertEqual(task.blockedReason, "waiting on legal")

        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(decoded.blockedReason, "waiting on legal")

        task.setStatus(.blocked, at: now)
        XCTAssertEqual(task.blockedReason, "waiting on legal", "Picking the same state keeps the reason")
        task.setStatus(.inProgress, at: now)
        XCTAssertNil(task.blockedReason)
        task.setStatus(.blocked, at: now)
        XCTAssertNil(task.blockedReason, "A reason does not come back with the state")

        task.setBlockedReason("   ")
        XCTAssertNil(task.blockedReason)
    }

    func testBlockedReasonNeedsTheBlockedState() {
        var open = TaskItem(title: "Açık", blockedReason: "ignored")
        XCTAssertNil(open.blockedReason)
        open.setBlockedReason("still ignored")
        XCTAssertNil(open.blockedReason)

        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","title":"Eski","createdAt":0,"status":"open","blockedReason":"stale"}"#
        let decoded = try? JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.blockedReason)
    }

    func testRecurringCompletionDropsBlockedReason() throws {
        let task = TaskItem(title: "Haftalık", status: .blocked, blockedReason: "QA", dueDate: now, recurrence: .daily)
        let (_, next) = try XCTUnwrap(task.completingRecurrence(at: now, calendar: calendar))
        XCTAssertEqual(next.status, .open)
        XCTAssertNil(next.blockedReason)
    }

    func testSidecarWrittenBeforeBlockedStateStillDecodes() throws {
        let id = UUID()
        let json = #"{"taskID":"\#(id.uuidString)","isInProgress":true}"#
        let entry = try JSONDecoder().decode(TaskSidecarEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.taskID, id)
        XCTAssertTrue(entry.isInProgress)
        XCTAssertFalse(entry.isBlocked)
        XCTAssertNil(entry.blockedReason)
    }

    func testCompletedTaskStaysInListUntilDayEndsAndArchiveMovesItToHistory() {
        var task = TaskItem(title: "Rapor")
        task.setStatus(.completed, at: now)
        XCTAssertFalse(task.isArchived)
        XCTAssertEqual(TaskListPresentation(tasks: [task], now: now, calendar: calendar).sections.map(\.kind), [.completedToday])

        let tomorrow = now.addingTimeInterval(86_400)
        XCTAssertTrue(TaskListPresentation(tasks: [task], now: tomorrow, calendar: calendar).sections.isEmpty)

        task.archive(at: now)
        let archived = TaskListPresentation(tasks: [task], now: now, calendar: calendar)
        XCTAssertTrue(archived.sections.isEmpty)
        XCTAssertEqual(archived.history.first?.tasks.first?.id, task.id)
    }

    func testPriorityThenDueOrdersWithinSection() {
        let low = TaskItem(title: "Düşük", createdAt: now, priority: .low)
        let high = TaskItem(title: "Yüksek", createdAt: now.addingTimeInterval(10), priority: .high)
        let none = TaskItem(title: "Yok", createdAt: now.addingTimeInterval(-10))
        let section = TaskListPresentation(tasks: [low, none, high], now: now, calendar: calendar).sections.first
        XCTAssertEqual(section?.tasks.map(\.title), ["Yüksek", "Düşük", "Yok"])
    }

    func testDueLabels() {
        let start = calendar.startOfDay(for: now)
        XCTAssertEqual(TaskDueFormatter.label(due: start, hasTime: false, now: now, calendar: calendar), "Today")
        XCTAssertEqual(TaskDueFormatter.label(due: start.addingTimeInterval(86_400 + 9 * 3_600), hasTime: true, now: now, calendar: calendar), "Tomorrow 09:00")
        XCTAssertEqual(TaskDueFormatter.label(due: start.addingTimeInterval(-86_400), hasTime: false, now: now, calendar: calendar), "Yesterday")
    }

    // MARK: Status and recurrence

    func testInProgressAndCompletionTimestamps() {
        var task = TaskItem(title: "Odak")
        task.setStatus(.inProgress, at: now)
        XCTAssertEqual(task.startedAt, now)
        task.setStatus(.completed, at: now.addingTimeInterval(60))
        XCTAssertNil(task.startedAt)
        XCTAssertEqual(task.completedAt, now.addingTimeInterval(60))
        task.setStatus(.open, at: now)
        XCTAssertNil(task.completedAt)
    }

    func testCompletingDailyRecurringTaskAdvancesToTomorrow() throws {
        let today = calendar.startOfDay(for: now)
        let task = TaskItem(
            title: "Su iç",
            dueDate: today,
            recurrence: TaskRecurrence(frequency: .daily, interval: 1, weekdays: nil)
        )
        let (history, next) = try XCTUnwrap(task.completingRecurrence(at: now, calendar: calendar))
        XCTAssertEqual(history.status, .completed)
        XCTAssertNotEqual(history.id, task.id)
        XCTAssertEqual(next.id, task.id)
        XCTAssertEqual(next.status, .open)
        XCTAssertEqual(next.dueDate, today.addingTimeInterval(86_400))
    }

    func testOverdueWeeklyRecurrenceJumpsPastToday() throws {
        let today = calendar.startOfDay(for: now)
        let threeWeeksAgo = today.addingTimeInterval(-21 * 86_400)
        let task = TaskItem(
            title: "Haftalık rapor",
            dueDate: threeWeeksAgo,
            recurrence: TaskRecurrence(frequency: .weekly, interval: 1, weekdays: nil)
        )
        let next = try XCTUnwrap(task.completingRecurrence(at: now, calendar: calendar)).next
        XCTAssertEqual(next.dueDate, today.addingTimeInterval(7 * 86_400))
    }

    func testNonRecurringTaskHasNoRecurrenceCompletion() {
        XCTAssertNil(TaskItem(title: "Tek sefer").completingRecurrence(at: now, calendar: calendar))
    }

    func testLegacyStatusesDecodeIntoThreeStates() throws {
        for (raw, expected) in [("backlog", TaskStatus.open), ("todo", .open), ("blocked", .blocked), ("inProgress", .inProgress), ("completed", .completed)] {
            let json = """
            {"id":"\(UUID().uuidString)","title":"x","createdAt":0,"status":"\(raw)"\(raw == "completed" ? ",\"completedAt\":10" : "")}
            """
            let task = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
            XCTAssertEqual(task.status, expected, raw)
        }
    }

    // MARK: Reminders mapping

    func testReminderRecordRoundTripKeepsFields() {
        let due = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15, minute: 30))!
        let meetingID = UUID()
        var task = TaskItem(
            title: "Sunumu gönder",
            notes: "Ek: taslak",
            createdAt: now,
            dueDate: due,
            dueHasTime: true,
            recurrence: TaskRecurrence(frequency: .weekly, interval: 2, weekdays: [6]),
            priority: .high,
            sourceMeetingID: meetingID
        )
        task.setStatus(.inProgress, at: now)

        let record = ReminderTaskMapper.record(from: task, identifier: "R1", calendar: calendar)
        XCTAssertEqual(record.priority, 1)
        XCTAssertEqual(record.alarmDate, due)
        XCTAssertEqual(record.dueDateComponents?.hour, 15)
        XCTAssertEqual(record.url, ReminderTaskMapper.meetingURL(meetingID))

        let restored = ReminderTaskMapper.task(
            from: record,
            sidecar: ReminderTaskMapper.sidecar(from: task),
            calendar: calendar
        )
        XCTAssertEqual(restored.id, task.id)
        XCTAssertEqual(restored.title, task.title)
        XCTAssertEqual(restored.notes, task.notes)
        XCTAssertEqual(restored.dueDate, due)
        XCTAssertTrue(restored.dueHasTime)
        XCTAssertEqual(restored.recurrence, task.recurrence)
        XCTAssertEqual(restored.priority, .high)
        XCTAssertEqual(restored.status, .inProgress)
        XCTAssertEqual(restored.sourceMeetingID, meetingID)
        XCTAssertEqual(restored.reminderIdentifier, "R1")
    }

    func testDayLevelDueHasNoAlarmAndNoTime() {
        let day = calendar.startOfDay(for: now)
        let record = ReminderTaskMapper.record(from: TaskItem(title: "Gün", dueDate: day), identifier: nil, calendar: calendar)
        XCTAssertNil(record.alarmDate)
        XCTAssertNil(record.dueDateComponents?.hour)
        let restored = ReminderTaskMapper.task(from: record, sidecar: nil, calendar: calendar)
        XCTAssertEqual(restored.dueDate, day)
        XCTAssertFalse(restored.dueHasTime)
    }

    func testReminderFromOtherDeviceGetsStableIDAndCompletedStateWins() {
        let record = ReminderRecord(
            identifier: "iphone-1",
            title: "Süt al",
            notes: nil,
            dueDateComponents: nil,
            priority: 7,
            recurrence: nil,
            isCompleted: true,
            completionDate: now,
            creationDate: now,
            url: nil,
            alarmDate: nil
        )
        let first = ReminderTaskMapper.task(from: record, sidecar: TaskSidecarEntry(taskID: UUID(), isInProgress: true), calendar: calendar)
        XCTAssertEqual(first.status, .completed)
        XCTAssertEqual(first.priority, .low)
        let a = ReminderTaskMapper.task(from: record, sidecar: nil, calendar: calendar)
        let b = ReminderTaskMapper.task(from: record, sidecar: nil, calendar: calendar)
        XCTAssertEqual(a.id, b.id)
    }

    // MARK: Repository

    func testRemindersRepositorySaveLoadDeleteKeepsTaskIdentity() async throws {
        let store = FakeReminderStore()
        let repository = makeRepository(store: store)
        var task = TaskItem(title: "Kod incelemesi", createdAt: now)
        task.setStatus(.inProgress, at: now)

        try await repository.save(task)
        var loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.map(\.id), [task.id])
        XCTAssertEqual(loaded.first?.status, .inProgress)

        var renamed = try XCTUnwrap(loaded.first)
        renamed.title = "Kod incelemesi — PR 12"
        try await repository.save(renamed)
        loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Kod incelemesi — PR 12")
        XCTAssertEqual(store.listsCreated, 1)

        try await repository.delete(id: task.id)
        loaded = try await repository.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testReminderDeletedElsewhereIsRecreatedOnSave() async throws {
        let store = FakeReminderStore()
        let repository = makeRepository(store: store)
        let task = TaskItem(title: "Fatura", createdAt: now)
        try await repository.save(task)
        let identifier = try XCTUnwrap(store.records.keys.first)
        store.records[identifier] = nil

        var edited = task
        edited.title = "Faturayı öde"
        try await repository.save(edited)
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.map(\.title), ["Faturayı öde"])
        XCTAssertEqual(loaded.first?.id, task.id)
    }

    func testMigrationCopiesActiveAndRecentTasksOnce() async throws {
        let store = FakeReminderStore()
        let repository = makeRepository(store: store)
        let local = InMemoryTaskRepository()
        var recent = TaskItem(title: "Dün bitti", createdAt: now)
        recent.setStatus(.completed, at: now.addingTimeInterval(-86_400))
        var old = TaskItem(title: "Eski", createdAt: now)
        old.setStatus(.completed, at: now.addingTimeInterval(-90 * 86_400))
        var archived = TaskItem(title: "Arşiv", createdAt: now)
        archived.archive(at: now)
        local.tasks = [TaskItem(title: "Açık", createdAt: now), recent, old, archived]

        let migrated = try await repository.migrateIfNeeded(from: local)
        XCTAssertEqual(migrated, 2)
        XCTAssertEqual(Set(store.records.values.map(\.title)), ["Açık", "Dün bitti"])
        let again = try await repository.migrateIfNeeded(from: local)
        XCTAssertEqual(again, 0)
    }

    func testReconnectingImportsTasksAddedInLocalModeExactlyOnce() async throws {
        let store = FakeReminderStore()
        let local = InMemoryTaskRepository()
        let router = TaskRepositoryRouter(local: local, reminders: makeRepository(store: store), store: store)
        try await router.save(TaskItem(title: "First"))
        _ = await router.activate(preferReminders: true)
        _ = await router.activate(preferReminders: false)
        try await router.save(TaskItem(title: "Second"))
        _ = await router.activate(preferReminders: true)
        _ = await router.activate(preferReminders: true)
        XCTAssertEqual(store.records.values.map(\.title).sorted(), ["First", "Second"])
    }

    func testRouterFallsBackToLocalWithoutPermission() async throws {
        let store = FakeReminderStore()
        store.access = .notDetermined
        let local = InMemoryTaskRepository()
        let router = TaskRepositoryRouter(local: local, reminders: makeRepository(store: store), store: store)

        let status = await router.activate(preferReminders: true)
        XCTAssertEqual(status, .localNotConnected)
        try await router.save(TaskItem(title: "Yerel"))
        XCTAssertEqual(local.tasks.map(\.title), ["Yerel"])
        XCTAssertTrue(store.records.isEmpty)

        store.access = .denied
        let denied = await router.activate(preferReminders: true)
        XCTAssertEqual(denied, .localDenied)

        store.access = .authorized
        let connected = await router.activate(preferReminders: true)
        XCTAssertEqual(connected, .reminders(listTitle: "Crenel"))
        XCTAssertEqual(store.records.values.map(\.title), ["Yerel"])
        let byChoice = await router.activate(preferReminders: false)
        XCTAssertEqual(byChoice, .localByChoice)
    }

    // MARK: Notch

    func testCompactStatusPriorities() {
        let task = TaskItem(title: "Odak", status: .inProgress, startedAt: now)
        let calmEvent = Meeting(title: "Akşam", startDate: now.addingTimeInterval(3 * 3_600), endDate: now.addingTimeInterval(4 * 3_600), kind: .event)
        let soonMeeting = Meeting(title: "Standup", startDate: now.addingTimeInterval(5 * 60), endDate: now.addingTimeInterval(20 * 60), kind: .onlineMeeting)

        XCTAssertEqual(
            NotchStatusResolver.compactStatus(flow: .idle, nextMeeting: nil, activeTaskCount: 1, agendaItems: [calmEvent], focusedTask: task, now: now),
            .focus(task)
        )
        if case .agenda = NotchStatusResolver.compactStatus(flow: .idle, nextMeeting: nil, activeTaskCount: 1, agendaItems: [soonMeeting], focusedTask: task, now: now) {} else {
            XCTFail("An imminent meeting must take over the focused task")
        }
        XCTAssertEqual(
            NotchStatusResolver.compactStatus(flow: .recording(startedAt: now), nextMeeting: nil, activeTaskCount: 0, dictation: .transcribing, now: now),
            .dictation(.transcribing)
        )
    }

    func testDictationTaskCommandUsesSmartParsing() {
        let result = DictationCoordinator.taskParseResult(from: "yarın faturayı öde", now: now)
        XCTAssertEqual(result.title.lowercased(), "faturayı öde")
        XCTAssertNotNil(result.dueDate)
    }

    // MARK: Helpers

    private func makeRepository(store: FakeReminderStore) -> RemindersTaskRepository {
        let url = FileManager.default.temporaryDirectory.appending(path: "crenel-sidecar-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let fixedNow = now
        return RemindersTaskRepository(
            store: store,
            sidecar: TaskSidecarFile(url: url),
            calendar: calendar,
            now: { fixedNow }
        )
    }
}

private final class FakeReminderStore: ReminderStore, @unchecked Sendable {
    var access: ReminderAccessState = .authorized
    var records: [String: ReminderRecord] = [:]
    var listsCreated = 0
    private var listID: String?
    private var counter = 0

    func accessState() async -> ReminderAccessState { access }

    func requestAccess() async throws -> Bool {
        access = .authorized
        return true
    }

    func prepareList(preferredIdentifier: String?, title: String) async throws -> String {
        guard access == .authorized else { throw ReminderStoreError.accessDenied }
        if let listID { return listID }
        listsCreated += 1
        listID = "list-\(title)"
        return listID!
    }

    func fetch(listIdentifier: String, completedSince: Date) async throws -> [ReminderRecord] {
        records.values
            .filter { !$0.isCompleted || ($0.completionDate ?? .distantPast) >= completedSince }
            .sorted { ($0.identifier ?? "") < ($1.identifier ?? "") }
    }

    func save(_ record: ReminderRecord, listIdentifier: String) async throws -> String {
        var record = record
        if let identifier = record.identifier {
            guard records[identifier] != nil else { throw ReminderStoreError.reminderNotFound }
        } else {
            counter += 1
            record.identifier = "rem-\(counter)"
        }
        records[record.identifier!] = record
        return record.identifier!
    }

    func remove(identifier: String) async throws {
        records[identifier] = nil
    }
}

private final class InMemoryTaskRepository: TaskRepository, @unchecked Sendable {
    var tasks: [TaskItem] = []

    func prepare() async throws {}
    func loadAll() async throws -> [TaskItem] { tasks }
    func save(_ task: TaskItem) async throws {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }
    func delete(id: UUID) async throws { tasks.removeAll { $0.id == id } }
}
