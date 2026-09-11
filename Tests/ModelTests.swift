import Foundation
@main struct ModelTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InterviewBarTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = EventRepository(url: root.appendingPathComponent("events.json"))
        let seed = [InterviewEvent(company: "示例科技", date: Date(timeIntervalSince1970: 1900000000), isDeadline: true)]
        assert(seed.count == 1 && seed[0].isDeadline)
        try repository.save(seed)
        assert(tryLoad(repository) == seed)
        var edited = seed; edited[0].date = edited[0].date.addingTimeInterval(3600)
        try repository.save(edited)
        assert(tryLoad(repository) == edited)
        let backup = try EventRepository(url: repository.url.appendingPathExtension("backup")).load(); assert(backup == seed)
        var event = seed[0]
        assert(event.overdue(at: event.date.addingTimeInterval(1)))
        event.status = .completed
        assert(!event.overdue(at: event.date.addingTimeInterval(1)))
        event.company = "  "
        do { _ = try event.validated(); fatalError("Empty company accepted") } catch {}
        event.company = "测试"; event.link = "javascript:alert(1)"
        do { _ = try event.validated(); fatalError("Unsafe URL accepted") } catch {}
        event.link = "https://example.com/interview"; _ = try event.validated()
        let broken = Data("invalid JSON".utf8); try broken.write(to: repository.url)
        do { _ = try repository.load(); fatalError("Corrupt data accepted") } catch {}
        let preserved = try Data(contentsOf: repository.url); assert(preserved == broken)
        print("PASS: seed dates, deadline meaning, edit/reload, backup, overdue status, validation, corrupt-file preservation")
    }
    static func tryLoad(_ repository: EventRepository) -> [InterviewEvent] { try! repository.load() }
}
