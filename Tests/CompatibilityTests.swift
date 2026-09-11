import Foundation
@main struct CompatibilityTests {
 static func main() throws {
  let event = InterviewEvent(company: "测试公司")
  let data = try JSONEncoder().encode(event)
  var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  object.removeValue(forKey: "round")
  let legacy = try JSONDecoder().decode(InterviewEvent.self, from: JSONSerialization.data(withJSONObject: object))
  assert(legacy.round == nil && legacy.kindLabel == "面试")
  var current = legacy; current.round = "二面"
  let reloaded = try JSONDecoder().decode(InterviewEvent.self, from: JSONEncoder().encode(current))
  assert(reloaded.kindLabel == "面试 · 二面" && reloaded.date == legacy.date)
  current.status = .rejected
  assert(!current.overdue(at: Date().addingTimeInterval(86400)))
  let result = ApplicationResult(id: UUID(), company: "示例乙公司", role: "", status: .rejected, updatedAt: Date(), notes: "用户确认")
  let encoded = try JSONEncoder().encode(result)
  let decoded = try JSONDecoder().decode(ApplicationResult.self, from: encoded)
  assert(decoded.status == .rejected)
  let resultFields = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
  assert(resultFields["date"] == nil && resultFields["reminderMinutes"] == nil)
  print("PASS: legacy events load, round persisted without date changes, rejected status, undated outcome has no schedule or reminder")
 }
}
