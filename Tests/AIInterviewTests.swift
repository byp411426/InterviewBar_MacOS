import Foundation

@main struct AIInterviewTests {
    @MainActor static func main() throws {
        let text = "公司：示例制造\n诚邀参加AI面试，截止时间为2028年09月14日 23:59（北京时间），截止前任意时间完成。预留30分钟。若通过AI面试，将收到下一环节的面试安排。\n[拒绝AI面试链接](https://example.com/schoolOut/apply?type=1)"
        let draft = MailParser.parse(text, knownCompanies: ["示例制造"])
        assert(draft.kind == .aiInterview && draft.isDeadline && draft.day == "2028-09-14" && draft.time == "23:59")
        assert(!draft.rejected && draft.round.isEmpty && draft.link.isEmpty)
        let decoded = try MailModel.decode(#"{"company":"示例制造","kind":"ai_interview","round":"二面","date":"2028-09-14","time":"23:59","timing":"exact","isDeadline":true,"rejected":false,"link":"https://example.com/schoolOut/apply?type=1"}"#, source: text)
        assert(decoded.canSchedule && decoded.kind == .aiInterview && decoded.link.isEmpty && decoded.round.isEmpty)
        let noTime = try MailModel.decode(#"{"company":"示例制造","kind":"ai_interview","date":null,"time":null,"timing":"unknown"}"#, source: "诚邀参加AI面试，时间稍后通知")
        assert(!noTime.canSchedule && noTime.day.isEmpty && noTime.time.isEmpty)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-interview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory, notificationsAllowed: false)
        let old = store.events
        try store.importMail(decoded, capture: MailCapture(text: text), targetID: nil, expectedRow: nil)
        let reloaded = EventStore(directory: directory, notificationsAllowed: false)
        assert(reloaded.events.count == old.count + 1)
        assert(old.allSatisfy { reloaded.events.contains($0) })
        let ai = reloaded.events.first { $0.kind == .aiInterview }!
        assert(ai.isDeadline && dateText(ai.date, "yyyy-MM-dd HH:mm") == "2028-09-14 23:59")
        let sheet = try JSONDecoder().decode(SheetSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("application-sheet.json")))
        assert(sheet.rows.last![sheet.columns.firstIndex(of: "当前状态")!] == "AI面试-待进行")
        for kind in EventKind.allCases {
            let filter = EventKindFilter(rawValue: kind.rawValue)!
            assert(filter.matches(kind) && !filter.matches(nil))
            assert(EventKind.allCases.filter { filter.matches($0) } == [kind])
            assert(EventKindFilter.all.matches(kind))
        }
        assert(EventKindFilter.all.matches(nil))
        assert(!EventKindFilter.interview.matches(.aiInterview))
        let regular = MailParser.parse("公司：星河科技\n邀请您参加面试\n面试时间：2028年9月14日16:15", knownCompanies: [])
        assert(regular.kind == .interview && !regular.isDeadline)
        print("PASS: AI interview classification/deadline, decline URL exclusion, nullable time, legacy preservation, ledger persistence, four distinct type filters")
    }
}
