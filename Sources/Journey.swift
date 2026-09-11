import Foundation

struct JourneyWeek: Identifiable {
    let start: Date
    let end: Date
    let events: [InterviewEvent]
    var id: Date { start }
    var completed: [InterviewEvent] { events.filter { $0.status == .completed } }
    func count(_ kind: EventKind) -> Int { completed.filter { $0.kind == kind }.count }
}
enum JourneyStats {
    static var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = shanghai
        return value
    }
    static func weeks(_ events: [InterviewEvent]) -> [JourneyWeek] {
        let calendar = calendar
        let groups = Dictionary(grouping: events) { calendar.dateInterval(of: .weekOfYear, for: $0.date)!.start }
        return groups.keys.sorted(by: >).map { start in
            JourneyWeek(start: start, end: calendar.date(byAdding: .day, value: 6, to: start)!,
                        events: groups[start]!.sorted { $0.date < $1.date })
        }
    }
    static func nextEncouragement(excluding previous: String = "") -> String {
        Encouragement.lines.filter { $0 != previous }.randomElement() ?? Encouragement.lines[0]
    }
}

enum JourneyMetric: String, CaseIterable {
    case completed = "已完成", scheduled = "全部安排"
    func includes(_ event: InterviewEvent) -> Bool { self == .scheduled || event.status == .completed }
}
enum JourneyRange: String, CaseIterable {
    case eight = "近 8 周", twelve = "近 12 周", all = "全部时间"
    var count: Int? { switch self { case .eight: 8; case .twelve: 12; case .all: nil } }
}
struct JourneyChartWeek: Identifiable {
    let start: Date
    let events: [InterviewEvent]
    var id: String { dateText(start, "yyyy-MM-dd") }
    var end: Date { JourneyStats.calendar.date(byAdding: .day, value: 6, to: start)! }
    var label: String { dateText(start, "MM/dd") }
    func count(_ kind: EventKind) -> Int { events.filter { $0.kind == kind }.count }
}
extension JourneyStats {
    // Recent ranges end this Sunday. Future weeks are available under all time.
    static func chartWeeks(_ events: [InterviewEvent], now: Date, range: JourneyRange, metric: JourneyMetric) -> [JourneyChartWeek] {
        let cal = calendar
        let current = cal.dateInterval(of: .weekOfYear, for: now)!.start
        let dates = events.map { cal.dateInterval(of: .weekOfYear, for: $0.date)!.start }
        let end = range == .all ? max(current, dates.max() ?? current) : current
        let start = range.count.map { cal.date(byAdding: .weekOfYear, value: -($0 - 1), to: end)! } ?? min(current, dates.min() ?? current)
        let groups = Dictionary(grouping: events.filter { metric.includes($0) }) { cal.dateInterval(of: .weekOfYear, for: $0.date)!.start }
        var result: [JourneyChartWeek] = [], cursor = start
        // Iterate only calendar weeks; imported out-of-range dates cannot allocate unbounded UI data.
        while cursor <= end && result.count < 5200 {
            result.append(JourneyChartWeek(start: cursor, events: (groups[cursor] ?? []).sorted { $0.date < $1.date }))
            cursor = cal.date(byAdding: .weekOfYear, value: 1, to: cursor)!
        }
        return result
    }
    static func cumulative(_ weeks: [JourneyChartWeek], kind: EventKind, through index: Int) -> Int {
        weeks.prefix(index + 1).reduce(0) { $0 + $1.count(kind) }
    }
}
