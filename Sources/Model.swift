import Foundation

enum MailTiming: String, Codable, CaseIterable {
    case exact, dateOnly = "date_only", windowStart = "window_start", unknown
    var label: String { switch self { case .exact: "具体时间已知"; case .dateOnly: "只有日期，几点待通知"; case .windowStart: "从该日起陆续安排"; case .unknown: "日期与时间待通知" } }
}


enum EventKind: String, Codable, CaseIterable { case interview = "面试", exam = "笔试", assessment = "测评", aiInterview = "AI面试" }
enum EventKindFilter: String, CaseIterable {
    case all = "全部类型", interview = "面试", exam = "笔试", assessment = "测评", aiInterview = "AI面试"
    func matches(_ kind: EventKind?) -> Bool { self == .all || kind?.rawValue == rawValue }
}

enum EventStatus: String, Codable, CaseIterable { case pending = "待进行", completed = "已完成", cancelled = "已取消", rejected = "未通过" }
struct InterviewEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var company: String
    var role = ""
    var kind = EventKind.interview
    var date = Date()
    var isDeadline = false
    var status = EventStatus.pending
    var location = ""
    var link = ""
    var notes = ""
    var reminderMinutes = 30
    var createdAt = Date()
    var round: String?
    var kindLabel: String { kind == .interview && !(round ?? "").isEmpty ? "面试 · " + (round ?? "") : kind.rawValue }
    func overdue(at now: Date) -> Bool { status == .pending && date < now }
    func validated() throws -> InterviewEvent {
        var copy = self
        copy.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.company.isEmpty else { throw DataError.invalid("请填写公司名称。") }
        if !copy.link.isEmpty {
            guard let url = URL(string: copy.link), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw DataError.invalid("链接请填写完整的 http:// 或 https:// 地址。会议号可放在地点里。")
            }
        }
        guard [0, 5, 15, 30, 60, 1440].contains(reminderMinutes) else { throw DataError.invalid("提醒时间无效。") }
        return copy
    }
}
struct ApplicationResult: Identifiable, Codable {
    var id: UUID
    var company: String
    var role: String
    var status: EventStatus
    var updatedAt: Date
    var notes: String
}
struct UnscheduledEvent: Identifiable, Codable {
    var id = UUID()
    var company: String
    var role: String
    var kind: EventKind?
    var round: String
    var day: String
    var time: String
    var timing: MailTiming
    var timeNote: String
    var notes: String
    var location: String? = nil
    var link: String? = nil
    var createdAt = Date()
    // Optional fields keep records written by older versions readable.
    var status: EventStatus? = nil
    var isDeadline: Bool? = nil
    var recordStatus: EventStatus { status ?? .pending }
    var statusLabel: String { recordStatus == .pending ? "时间待通知" : recordStatus.rawValue }
    var displayCompany: String { company.isEmpty ? "公司待确认" : company }
    var displayTime: String {
        if day.isEmpty { return "日期与时间待通知" }
        if timing == .windowStart { return day + " 起陆续安排，具体时间待通知" }
        return day + (time.isEmpty ? "，具体时间待通知" : " " + time + "（信息待确认）")
    }
}

enum DataError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
struct EventFile: Codable { var version = 1; var events: [InterviewEvent] }
struct EventRepository {
    let url: URL
    func load() throws -> [InterviewEvent] {
        let file = try JSONDecoder().decode(EventFile.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw DataError.invalid("日程文件版本暂不支持。原文件已保留。") }
        guard Set(file.events.map(\.id)).count == file.events.count else { throw DataError.invalid("日程中存在重复标识，原文件已保留。") }
        return try file.events.map { try $0.validated() }
    }
    func save(_ events: [InterviewEvent]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(EventFile(events: events))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if FileManager.default.fileExists(atPath: url.appendingPathExtension("backup").path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.appendingPathExtension("backup").path)
        }
    }
}
let shanghai = TimeZone(identifier: "Asia/Shanghai")!
func dateText(_ date: Date, _ format: String = "M月d日 EEEE HH:mm") -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = shanghai; formatter.dateFormat = format
    return formatter.string(from: date)
}
