import Foundation

@main struct UnscheduledDeletionTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pending-delete-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory, notificationsAllowed: false)
        let known = try MailModel.decode(#"{"company":"示例科技","kind":"exam","date":"2028-09-15","timing":"window_start"}"#, source: "示例科技笔试9月15日起，具体时间待通知")
        let unknown = try MailModel.decode(#"{"company":null,"kind":null,"timing":"unknown"}"#, source: "后续安排待通知")
        try store.importMail(known, capture: MailCapture(text: "虚构预通知甲"), targetID: nil, expectedRow: nil)
        try store.importMail(unknown, capture: MailCapture(text: "虚构预通知乙"), targetID: nil, expectedRow: nil)
        let first = store.unscheduled[0].id, second = store.unscheduled[1].id
        // Old files without status decode as pending; status changes never invent a time.
        assert(store.unscheduled.allSatisfy { $0.recordStatus == .pending })
        for status in [EventStatus.completed, .cancelled, .rejected, .pending] {
            assert(store.setUnscheduledStatus(second, status))
            let loaded = EventStore(directory: directory, notificationsAllowed: false)
            assert(loaded.unscheduled[1].recordStatus == status && loaded.unscheduled[1].time.isEmpty)
        }
        var edit = store.unscheduled[1]
        edit.company = "修正公司"; edit.kind = .aiInterview; edit.status = .completed
        assert(store.saveUnscheduled(edit))
        assert(store.unscheduled[1].company == "修正公司" && store.unscheduled[1].recordStatus == .completed)
        edit.day = "2028-02-30"
        assert(!store.saveUnscheduled(edit))
        assert(store.unscheduled[1].day.isEmpty)
        let preservedNames = ["events.json", "application-results.json", "application-sheet.json", "import-history.json"]
        let preserved = try preservedNames.map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        assert(store.deleteUnscheduled(first))
        assert(store.unscheduled.map(\.id) == [second])
        let reloaded = EventStore(directory: directory, notificationsAllowed: false)
        assert(reloaded.unscheduled.map(\.id) == [second])
        assert(store.deleteUnscheduled(first)) // A stale menu must not delete a different record.
        assert(store.unscheduled.map(\.id) == [second])
        for (name, data) in zip(preservedNames, preserved) {
            let actual = try Data(contentsOf: directory.appendingPathComponent(name))
            assert(actual == data)
        }
        let pendingURL = directory.appendingPathComponent("unscheduled-events.json")
        let pendingData = try Data(contentsOf: pendingURL)
        // Force an atomic-write failure without relying on user/file permission differences.
        try FileManager.default.removeItem(at: pendingURL)
        try FileManager.default.createDirectory(at: pendingURL, withIntermediateDirectories: false)
        assert(!store.deleteUnscheduled(second))
        assert(store.unscheduled.map(\.id) == [second] && store.error != nil)
        try FileManager.default.removeItem(at: pendingURL)
        try pendingData.write(to: pendingURL)
        assert(store.deleteUnscheduled(second)) // Unknown companies are deletable by stable ID.
        assert(store.unscheduled.isEmpty)
        assert(EventStore(directory: directory, notificationsAllowed: false).unscheduled.isEmpty)
        // A corrupt source must stay untouched rather than being replaced with an empty file.
        let corrupt = Data("invalid".utf8)
        try corrupt.write(to: pendingURL)
        let invalid = EventStore(directory: directory, notificationsAllowed: false)
        assert(!invalid.deleteUnscheduled(second))
        let actual = try Data(contentsOf: pendingURL)
        assert(actual == corrupt)

        let editDirectory = directory.appendingPathComponent("edits")
        let edits = EventStore(directory: editDirectory, notificationsAllowed: false)
        try edits.importMail(known, capture: MailCapture(text: "待修正时间"), targetID: nil, expectedRow: nil)
        var corrected = edits.unscheduled[0]
        let stableID = corrected.id
        corrected.day = "2028-09-16"; corrected.time = "16:15"; corrected.timing = .exact
        corrected.kind = .aiInterview; corrected.status = .completed; corrected.isDeadline = true
        assert(edits.saveUnscheduled(corrected))
        let reopened = EventStore(directory: editDirectory, notificationsAllowed: false)
        assert(reopened.unscheduled.isEmpty && reopened.events.count == 1)
        assert(reopened.events[0].id == stableID && reopened.events[0].status == .completed && reopened.events[0].kind == .aiInterview && reopened.events[0].isDeadline)
        assert(dateText(reopened.events[0].date, "yyyy-MM-dd HH:mm") == "2028-09-16 16:15")
        try edits.importMail(known, capture: MailCapture(text: "预通知待保留"), targetID: nil, expectedRow: nil)
        let closedID = edits.unscheduled[0].id
        assert(edits.setUnscheduledStatus(closedID, .completed))
        try edits.importMail(known, capture: MailCapture(text: "不同正文的新预通知"), targetID: nil, expectedRow: nil)
        assert(edits.unscheduled.count == 2 && edits.unscheduled[0].id == closedID && edits.unscheduled[0].recordStatus == .completed)
        print("PASS: status transitions, legacy defaults, unknown-time completion, correction, stable-ID promotion, closed-history protection, deletion, persistence, write failure and corrupt-file protection")
    }
}
