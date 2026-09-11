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
