import Foundation
import CryptoKit

struct MailCapture: Codable {
    var id = UUID()
    var text: String
    var title = ""
    var sourceURL = ""
    var capturedAt = Date()
    var digest: String { SHA256.hash(data: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map { String(format: "%02x", $0) }.joined() }
}

struct MailDraft: Equatable {
    var company = "", role = "", round = "", day = "", time = "", location = "", link = ""
    var kind = EventKind.interview
    var rejected = false
    var isDeadline = false
    var timing = MailTiming.exact
    var timeNote = ""
    var kindUncertain = false
    var canSchedule: Bool { timing == .exact && !day.isEmpty && !time.isEmpty && !company.isEmpty && !kindUncertain }
    var warnings: [String] = []

    // A company identifies an application, not an individual interview.
    // Replacing an arrangement always requires an explicit selection.
    private func sameArrangementFields(company oldCompany: String, kind oldKind: EventKind?, round oldRound: String, role oldRole: String) -> Bool {
        let clean = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !clean(company).isEmpty && MailParser.companyKey(oldCompany) == MailParser.companyKey(company)
            && !kindUncertain && oldKind == kind && clean(oldRound) == clean(round)
            && (clean(role).isEmpty || clean(oldRole).isEmpty || clean(oldRole) == clean(role))
    }
    func canUpdate(_ event: InterviewEvent) -> Bool {
        event.status == .pending && (canSchedule || rejected)
            && sameArrangementFields(company: event.company, kind: event.kind, round: event.round ?? "", role: event.role)
    }
    func canUpdate(_ event: UnscheduledEvent) -> Bool {
        !rejected && event.recordStatus == .pending
            && sameArrangementFields(company: event.company, kind: event.kind, round: event.round, role: event.role)
    }

    func event() throws -> InterviewEvent {
        guard !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DataError.invalid("请先填写公司名称。") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = shanghai
        formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
        let value = day + " " + time
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw DataError.invalid("请核对时间，格式为 2026-09-14 和 16:15。缺少的时间需要手动补齐。")
        }
        return try InterviewEvent(company: company, role: role, kind: kind, date: date, isDeadline: isDeadline, status: .pending,
            location: location, link: link, round: round.isEmpty ? nil : round).validated()
    }
}

enum MailParser {
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    static func first(_ pattern: String, _ text: String) -> String { matches(pattern, text).first?.dropFirst().first ?? "" }
    static func companyKey(_ name: String) -> String {
        name.replacingOccurrences(of: "(?:股份)?(?:有限责任|有限)?公司$|集团$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isDeclineLink(_ link: String, in text: String) -> Bool {
        guard let range = text.range(of: link) else { return false }
        let prefix = String(text[..<range.lowerBound].suffix(100))
        let label = prefix.components(separatedBy: "\n").last ?? prefix
        return !matches("(?:拒绝|放弃|推迟|结束投递|退订)[^。！？\n]{0,70}$", label).isEmpty
    }
    static func parse(_ text: String, knownCompanies: [String], now: Date = Date()) -> MailDraft {
        var draft = MailDraft()
        draft.company = first("(?:公司名称|公司|企业)[：:]\\s*([^\\n，。！!]{2,30})", text)
        if draft.company.isEmpty { draft.company = first("感谢(?:您)?关注\\s*([^！!，,。\\n]{2,30})", text) }
        if draft.company.isEmpty { draft.company = first("【([^】]{2,30}?)(?:校招|招聘)】", text) }
        if draft.company.isEmpty { draft.company = first("(?:联系人[：:]\\s*)?([^\\s：:，,。]{2,20})(?:校招HR|招聘HR)", text) }
        if let known = knownCompanies.sorted(by: { $0.count > $1.count }).first(where: { !companyKey($0).isEmpty && companyKey($0) == companyKey(draft.company) }) { draft.company = known }
        draft.role = first("(?:岗位名称|应聘岗位|职位名称|岗位|职位)[：:]\\s*([^\\n，。]{2,50})", text)
        if draft.role.isEmpty { draft.role = first("邀请您(?:参加|参与)\\s*([^\\n，。]{2,50}?)岗位", text) }
        draft.round = first("(一面|二面|三面|四面|终面|初面|复试|第[一二三四五12345]轮)", text)
        draft.rejected = !matches("(未能通过|未通过(?:本次)?(?:面试|笔试|测评|筛选)|很遗憾|暂不匹配|不予录用)", text).isEmpty
        if !matches("(?i)(AI\\s*(?:视频)?面试|人工智能面试|机器面试)", text).isEmpty { draft.kind = .aiInterview }
        else if !matches("(面试日期|面试时间|邀请[^\\n。]{0,70}面试)", text).isEmpty { draft.kind = .interview }
        else if !matches("(测评|测验|性格测试)", text).isEmpty { draft.kind = .assessment }
        else if text.contains("笔试") || text.contains("在线考试") { draft.kind = .exam }
        draft.isDeadline = draft.kind != .interview && (text.contains("截止") || text.contains("之前完成") || text.contains("前完成"))
        let dates = matches("(?<![0-9])(?:(20[0-9]{2})[年/.-])?([0-9]{1,2})[月/.-]([0-9]{1,2})日?(?![0-9])", text).filter {
            (!$0[1].isEmpty || $0[0].contains("月") || $0[0].contains("/")) && (1...12).contains(Int($0[2]) ?? 0) && (1...31).contains(Int($0[3]) ?? 0)
        }
        if let found = dates.first {
            let year = Int(found[1]) ?? Int(dateText(now, "yyyy"))!
            draft.day = String(format: "%04d-%02d-%02d", year, Int(found[2]) ?? 0, Int(found[3]) ?? 0)
            if found[1].isEmpty { draft.warnings.append("邮件未注明年份，暂按 \(year) 年，请核对。") }
            if Set(dates.map { $0[0] }).count > 1 { draft.warnings.append("发现多个日期，请选择本次安排对应的日期。") }
        } else { draft.warnings.append("没有识别到日期，请手动补齐；不会默认使用今天。") }
        let times = matches("(?<![0-9])([01]?[0-9]|2[0-3])[：:]([0-5][0-9])(?![0-9])", text)
        if let found = times.first {
            var hour = Int(found[1]) ?? 0
            if hour < 12 && !matches("(?:下午|晚上)\\s*" + NSRegularExpression.escapedPattern(for: found[0]), text).isEmpty { hour += 12 }
            draft.time = String(format: "%02d:%02d", hour, Int(found[2]) ?? 0)
            if Set(times.map { $0[0] }).count > 1 { draft.warnings.append("发现多个时间，请核对开始时间或截止时间。") }
        } else { draft.warnings.append("没有识别到具体时刻，请补齐；不会自动设为午夜。") }
        draft.link = first("(https?://[^\\s<>\"）)]+)", text).trimmingCharacters(in: CharacterSet(charactersIn: "。，,；;"))
        if isDeclineLink(draft.link, in: text) { draft.link = "" }
        if draft.kind != .interview { draft.round = "" }
        draft.location = first("(?:会议号|会议ID|地点)[：:]\\s*([^\\n）)；;]{2,80})", text)
        if draft.location.isEmpty && text.contains("视频面试") { draft.location = "视频面试" }
        if draft.company.isEmpty { draft.warnings.append("没有可靠识别出公司，请手动填写。") }
        if draft.rejected { draft.warnings.append("识别到未通过的表述，请确认是否是本次投递结果，避免把历史经历当成拒信。") }
        return draft
    }
}

// A write-ahead journal makes an interrupted two-table update recoverable.
enum ImportTransaction {
    static let names: Set<String> = ["events.json", "application-sheet.json", "application-results.json", "import-history.json", "unscheduled-events.json"]
    static func recover(in directory: URL) throws {
        let journal = directory.appendingPathComponent("import-transaction.json")
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let values = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: journal))
        guard !values.isEmpty, Set(values.keys).isSubset(of: names) else { throw DataError.invalid("导入恢复文件异常，已保留原文件。") }
        for name in values.keys.sorted() {
            let file = directory.appendingPathComponent(name)
            try values[name]!.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        try FileManager.default.removeItem(at: journal)
    }
    static func commit(_ values: [String: Data], in directory: URL) throws {
        guard !values.isEmpty, Set(values.keys).isSubset(of: names) else { throw DataError.invalid("导入文件无效。") }
        try recover(in: directory)
        let fm = FileManager.default
        let backup = directory.appendingPathComponent("mail-import-backups/" + UUID().uuidString)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in values.keys {
            let file = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path) {
                let target = backup.appendingPathComponent(name)
                try Data(contentsOf: file).write(to: target, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            }
        }
        let journal = directory.appendingPathComponent("import-transaction.json")
        try JSONEncoder().encode(values).write(to: journal, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        try recover(in: directory)
    }
}

extension Notification.Name { static let mailImportCommitted = Notification.Name("InterviewBar.mailImportCommitted") }
