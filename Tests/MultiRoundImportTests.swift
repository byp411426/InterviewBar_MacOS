import Foundation

@main struct MultiRoundImportTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("multi-round-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory, notificationsAllowed: false)
        var draft = MailDraft()
        draft.company = "示例科技"; draft.role = "Java开发"; draft.day = "2028-09-15"; draft.time = "17:00"
        var first = try draft.event() // Legacy data has no round number.
        first.status = .completed; first.notes = "第一场实际完成的记录"
        assert(store.save(first))

        // A second invitation without an AI-recognized round is a separate event.
        draft.day = "2028-09-17"; draft.time = "15:00"
        assert(!draft.canUpdate(first))
        try store.importMail(draft, capture: MailCapture(text: "下一场邀请，轮次未知"), targetID: nil, expectedRow: nil)
        assert(store.events.count == 2 && store.events.first { $0.id == first.id } == first)
        var second = store.events.first { $0.id != first.id }!
        second.round = "二面"; second.status = .completed
        assert(store.save(second))
        draft.round = "三面"; draft.day = "2028-09-20"
        try store.importMail(draft, capture: MailCapture(text: "第三轮邀请"), targetID: nil, expectedRow: nil)
        assert(store.events.count == 3 && store.events.filter { $0.status == .completed }.count == 2)
        assert(store.events.first { $0.id == first.id } == first)
        assert(store.events.first { $0.id == second.id } == second)

        // Even a stale or manually supplied ID cannot overwrite closed history.
        let names = ["events.json", "unscheduled-events.json", "application-sheet.json", "application-results.json", "import-history.json"]
        let before = try names.map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        let capturesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("mail-captures").path).count
        for old in [first, second] {
            do {
                try store.importMail(draft, capture: MailCapture(text: "禁止覆盖" + old.id.uuidString), targetID: old.id, expectedRow: nil)
                assertionFailure("Closed history was overwritten")
            } catch {}
        }
        for (name, data) in zip(names, before) {
            let actual = try Data(contentsOf: directory.appendingPathComponent(name))
            assert(actual == data)
        }
        let capturesAfter = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("mail-captures").path).count
        assert(capturesAfter == capturesBefore)

        // Explicit same-round rescheduling preserves identity; next rounds cannot reuse it.
        let third = store.events.first { $0.round == "三面" }!
        draft.time = "16:30"
        assert(draft.canUpdate(third))
        try store.importMail(draft, capture: MailCapture(text: "三面改期到16:30"), targetID: third.id, expectedRow: nil)
        assert(store.events.count == 3 && dateText(store.events.first { $0.id == third.id }!.date, "HH:mm") == "16:30")
        for round in ["", "四面"] {
            draft.round = round
            assert(!draft.canUpdate(third))
            do {
                try store.importMail(draft, capture: MailCapture(text: "禁止跨轮覆盖" + round), targetID: third.id, expectedRow: nil)
                assertionFailure("Different round accepted")
            } catch {}
        }
        draft.round = "三面"
        let staleStore = EventStore(directory: directory, notificationsAllowed: false)
        store.setStatus(store.events.first { $0.id == third.id }!, .completed)
        do {
            try staleStore.importMail(draft, capture: MailCapture(text: "打开窗口后旧记录被完成"), targetID: third.id, expectedRow: nil)
            assertionFailure("Stale target overwrote completed event")
        } catch {}
        draft.rejected = true
        try store.importMail(draft, capture: MailCapture(text: "后续投递结果通知"), targetID: nil, expectedRow: nil)
        assert(store.events.filter { $0.status == .completed }.count == 3 && store.results.count == 1)

        // Unknown-time invitations are also independent unless the user selects one explicitly.
        draft.rejected = false; draft.round = ""; draft.time = ""; draft.timing = .dateOnly
        try store.importMail(draft, capture: MailCapture(text: "未知轮次预通知一"), targetID: nil, expectedRow: nil)
        let pending = store.unscheduled[0]
        try store.importMail(draft, capture: MailCapture(text: "未知轮次预通知二"), targetID: nil, expectedRow: nil)
        assert(store.unscheduled.count == 2 && store.unscheduled[0].id == pending.id)
        draft.time = "09:00"; draft.timing = .exact
        try store.importMail(draft, capture: MailCapture(text: "明确补全预通知一"), targetID: nil, expectedRow: nil, pendingTargetID: pending.id)
        assert(store.unscheduled.count == 1 && store.events.contains { $0.id == pending.id })
        assert(store.events.first { $0.id == first.id } == first)
        let reopened = EventStore(directory: directory, notificationsAllowed: false)
        assert(reopened.events == store.events && reopened.events.filter { $0.status == .completed }.count == 3)
        print("PASS: independent first/second/third rounds, missing rounds, completed history, atomic rejection, explicit rescheduling, stale targets, rejection notices, explicit pending promotion and reload")
    }
}
