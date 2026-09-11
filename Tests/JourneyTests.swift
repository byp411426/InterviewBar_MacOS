import Foundation
@main struct JourneyTests {
    @MainActor static func main() throws {
        func date(_ value: String) -> Date {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = shanghai
            return f.date(from: value)!
        }
        let sun = InterviewEvent(company: "示例甲", kind: .exam, date: date("2027-01-03 23:59"), status: .completed)
        let mon = InterviewEvent(company: "示例乙", kind: .aiInterview, date: date("2027-01-04 00:00"), status: .completed)
        let pending = InterviewEvent(company: "示例丙", date: date("2027-01-01 10:00"))
        let cancelled = InterviewEvent(company: "示例丁", date: date("2027-01-01 11:00"), status: .cancelled)
        let weeks = JourneyStats.weeks([sun, mon, pending, cancelled])
        assert(weeks.count == 2)
        assert(dateText(weeks[1].start, "yyyy-MM-dd") == "2026-12-28")
        assert(weeks[1].completed.count == 1 && weeks[1].count(.exam) == 1)
        assert(weeks[0].count(.aiInterview) == 1 && weeks[0].count(.interview) == 0)
        assert(JourneyStats.weeks([]).isEmpty)
        assert((100...200).contains(Encouragement.lines.count))
        assert(Set(Encouragement.lines).count == Encouragement.lines.count)
        for _ in 0..<100 { assert(JourneyStats.nextEncouragement(excluding: Encouragement.lines[0]) != Encouragement.lines[0]) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EventStore(directory: root, notificationsAllowed: false)
        assert(store.events.isEmpty)
        assert(store.save(pending)); store.setStatus(pending, .completed)
        assert(JourneyStats.weeks(store.events)[0].completed.count == 1)
        let reload = EventStore(directory: root, notificationsAllowed: false)
        assert(reload.events.count == 1 && reload.events[0].status == .completed)
        reload.setStatus(reload.events[0], .pending)
        assert(JourneyStats.weeks(reload.events)[0].completed.isEmpty)
        assert(reload.events.count == 1)
        print("PASS: weekly year boundary, four kinds, explicit completion, persistence, empty onboarding, \(Encouragement.lines.count) unique encouragements")
    }
}
