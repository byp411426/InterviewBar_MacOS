import Foundation

@main struct ModelMailTests {
    @MainActor static func main() async throws {
        let content = #"{"company":"示例智能","role":null,"round":null,"kind":"exam","date":"2026-09-15","time":null,"timing":"window_start","timeNote":"笔试自9.15启动，将在开始前一周陆续发放链接","isDeadline":false,"rejected":false,"location":"Showmebug平台线上笔试","link":null,"warnings":["具体时间待通知"]}"#
        let draft = try MailModel.decode(content, source: "示例智能笔试自9.15启动")
        assert(draft.company == "示例智能" && draft.role.isEmpty && draft.time.isEmpty && !draft.canSchedule && draft.timing == .windowStart)
        let wrongRound = try MailModel.decode(#"{"company":"测试","kind":"exam","round":"笔试","timing":"unknown"}"#, source: "进入下一轮笔试")
        assert(wrongRound.round.isEmpty)
        let nulls = #"{"company":null,"role":null,"round":null,"kind":null,"date":null,"time":null,"timing":"unknown","timeNote":null,"isDeadline":null,"rejected":null,"location":null,"link":null,"warnings":[]}"#
        let empty = try MailModel.decode(nulls, source: "稍后通知")
        assert(empty.company.isEmpty && empty.day.isEmpty && empty.time.isEmpty && empty.kindUncertain)
        let bad = try MailModel.decode(#"{"company":"测试","kind":"exam","date":"2026-02-30","time":"99:99","timing":"exact","link":"https://example.com/invented"}"#, source: "没有日期和链接")
        assert(bad.day.isEmpty && bad.time.isEmpty && bad.link.isEmpty && !bad.canSchedule)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("model-mail-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory, notificationsAllowed: false)
        let original = store.events
        try store.importMail(draft, capture: MailCapture(text: "示例智能预通知测试"), targetID: nil, expectedRow: nil)
        assert(store.events == original && store.unscheduled.count == 1)
        assert(store.unscheduled[0].day == "2026-09-15" && store.unscheduled[0].time.isEmpty)
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.unscheduled[0])) as! [String: Any]
        assert(fields["date"] == nil && fields["reminderMinutes"] == nil)
        let reopened = EventStore(directory: directory, notificationsAllowed: false)
        assert(reopened.unscheduled.count == 1 && reopened.events == original)
        try store.importMail(empty, capture: MailCapture(text: "未知公司未知时间测试"), targetID: nil, expectedRow: nil)
        assert(store.unscheduled.last?.company == "" && store.unscheduled.last?.day == "")
        let exact = try MailModel.decode(#"{"company":"示例智能","kind":"exam","date":"2026-09-15","time":"14:30","timing":"exact","isDeadline":false,"rejected":false}"#, source: "笔试2026-09-15 14:30")
        let pendingID = store.unscheduled.first { $0.company == draft.company }!.id
        try store.importMail(exact, capture: MailCapture(text: "示例智能确定时间测试"), targetID: nil, expectedRow: nil, pendingTargetID: pendingID)
        assert(store.events.count == original.count + 1 && store.unscheduled.count == 1)
        let endpoint = try ModelConfiguration(baseURL: "https://api.example.com", model: "test").endpoint
        assert(endpoint.absoluteString == "https://api.example.com/v1/chat/completions")
        let config = ModelConfiguration(baseURL: "https://api.example.com", model: "deepseek-v4-flash")
        let sample = MailCapture(text: "示例智能笔试")
        let official = ModelConfiguration(baseURL: "https://api.deepseek.com", model: "deepseek-flash")
        let officialEndpoint = try official.endpoint
        assert(officialEndpoint.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        assert((MailModel.requestBody(sample, configuration: official)["thinking"] as? [String: String])?["type"] == "disabled")
        let body = MailModel.requestBody(sample, configuration: config)
        assert((body["thinking"] as? [String: String])?["type"] == "disabled")
        assert(MailModel.requestBody(sample, configuration: config, fast: false)["thinking"] == nil)
        assert(MailModel.requestBody(sample, configuration: ModelConfiguration(baseURL: config.baseURL, model: "another-model"))["thinking"] == nil)
        let cache = MailModelCache()
        let cacheKey = try MailModelCache.key(sample, configuration: config)
        let now = Date()
        await cache.put(draft, key: cacheKey, now: now)
        let cached = await cache.value(cacheKey, now: now.addingTimeInterval(599))
        assert(cached?.company == "示例智能" && cached?.time == "")
        let expired = await cache.value(cacheKey, now: now.addingTimeInterval(601))
        assert(expired == nil)
        var nextDay = sample; nextDay.capturedAt = sample.capturedAt.addingTimeInterval(86400)
        let nextKey = try MailModelCache.key(nextDay, configuration: config)
        let changedKey = try MailModelCache.key(MailCapture(text: "不同邮件"), configuration: config)
        let providerKey = try MailModelCache.key(sample, configuration: ModelConfiguration(baseURL: "https://example.com", model: config.model))
        assert(cacheKey != nextKey && cacheKey != changedKey && cacheKey != providerKey)
        print("PASS: fast-mode request, cache identity and expiry; nullable model fields, window start, no invented date/time/link, blank-field persistence, no timed reminders, reload, later exact schedule")
    }
}
