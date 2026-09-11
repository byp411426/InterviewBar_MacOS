import Foundation

@main struct MailImportTests {
    @MainActor static func main() throws {
        let text = """
        感谢关注星河科技集团！很高兴地通知您已经通过了我们的笔试，并进入了面试环节。
        现邀请您参加全栈开发工程师岗位的面试。
        面试日期：2028年9月14日 星期四
        面试时间：16:15
        面试时长：约30-40分钟
        面试形式：视频面试
        面试链接：https://example.com/interview?code=fixture
        会议号：123456
        面试可能会推迟5-15分钟开始。
        """
        let draft = MailParser.parse(text, knownCompanies: ["星河科技"])
        assert(draft.company == "星河科技" && draft.role == "全栈开发工程师")
        assert(draft.kind == .interview && !draft.rejected && draft.day == "2028-09-14" && draft.time == "16:15")
        assert(draft.warnings.isEmpty && draft.location == "123456" && draft.link.contains("example.com"))
        let missing = MailParser.parse("公司：测试\n邀请您参加面试", knownCompanies: [])
        assert(missing.day.isEmpty && missing.time.isEmpty)
        do { _ = try missing.event(); assertionFailure("Missing time accepted") } catch {}
        var invalid = draft; invalid.day = "2026-02-30"
        do { _ = try invalid.event(); assertionFailure("Impossible date accepted") } catch {}
        let exam = MailParser.parse("公司：测试\n笔试截止时间：2026/09/18 23:59", knownCompanies: [])
        assert(exam.kind == .exam && exam.isDeadline)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("interviewbar-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sheet = SheetSnapshot(title: "test", importedAt: Date(), columns: ["公司", "岗位", "当前状态", "备注"], rows: [["星河科技", "全栈开发", "笔试", "保留备注"], ["示例乙公司", "", "未通过", "保持原状"]])
        try JSONEncoder().encode(sheet).write(to: directory.appendingPathComponent("application-sheet.json"))
        let store = EventStore(directory: directory, notificationsAllowed: false)
        assert(store.save(InterviewEvent(company: "星河科技", date: Date())))
        let original = store.events.first { $0.company == "星河科技" }!
        let count = store.events.count
        let capture = MailCapture(text: text)
        try store.importMail(draft, capture: capture, targetID: original.id, expectedRow: sheet.rows[0])
        assert(store.events.count == count && store.events.first { $0.id == original.id }?.role == "全栈开发工程师")
        let loaded = try JSONDecoder().decode(SheetSnapshot.self, from: Data(contentsOf: directory.appendingPathComponent("application-sheet.json")))
        assert(loaded.rows.count == 2 && loaded.rows[1].prefix(4) == sheet.rows[1][...])
        assert(loaded.rows[0][3].contains("保留备注") && loaded.rows[0][2].contains("面试"))
        do { try store.importMail(draft, capture: capture, targetID: original.id, expectedRow: loaded.rows[0]); assertionFailure("Duplicate accepted") } catch {}
        let reopened = EventStore(directory: directory, notificationsAllowed: false)
        assert(reopened.events == store.events)
        let recoveryDir = directory.appendingPathComponent("recovery")
        try FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        let writes = ["events.json": Data("new-events".utf8), "application-sheet.json": Data("new-sheet".utf8)]
        try JSONEncoder().encode(writes).write(to: recoveryDir.appendingPathComponent("import-transaction.json"))
        try writes["events.json"]!.write(to: recoveryDir.appendingPathComponent("events.json"))
        try ImportTransaction.recover(in: recoveryDir)
        let restored = try Data(contentsOf: recoveryDir.appendingPathComponent("application-sheet.json"))
        assert(restored == writes["application-sheet.json"]!)
        print("PASS: mail extraction, missing/invalid dates, deadline, existing-event merge, ledger preservation, duplicate rejection, reload, interrupted transaction recovery")
    }
}
