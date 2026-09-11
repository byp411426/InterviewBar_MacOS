import Foundation

struct WidgetEvent: Codable, Identifiable {
    let id: UUID
    let company: String
    let kind: String
    let date: Date
    let isDeadline: Bool
}
struct WidgetSnapshot: Codable {
    let updatedAt: Date
    let upcoming: [WidgetEvent]
    let completedDates: [String: [Date]]
    static let empty = WidgetSnapshot(updatedAt: .distantPast, upcoming: [], completedDates: [:])
    func next(at now: Date) -> WidgetEvent? { upcoming.first { $0.date > now } }
    func count(_ kind: String, at now: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        return (completedDates[kind] ?? []).filter { $0 >= week.start && $0 < week.end }.count
    }
}
#if !WIDGET_EXTENSION
extension WidgetSnapshot {
    static func make(events: [InterviewEvent], now: Date) -> WidgetSnapshot {
        WidgetSnapshot(updatedAt: now, upcoming: events.filter { $0.status == .pending && $0.date > now }.sorted { $0.date < $1.date }.map {
            WidgetEvent(id: $0.id, company: $0.company, kind: $0.kindLabel, date: $0.date, isDeadline: $0.isDeadline)
        }, completedDates: Dictionary(grouping: events.filter { $0.status == .completed }, by: { $0.kind.rawValue }).mapValues { $0.map(\.date) })
    }
}
#endif
