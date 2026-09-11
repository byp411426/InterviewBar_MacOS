import Foundation

@main struct ModelGatewayTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = ModelUsageLedger(url: directory.appendingPathComponent("usage.json"))
        let capture = MailCapture(text: "虚构科技笔试，2028年9月18日14:30。")
        let content = #"{"company":"虚构科技","kind":"exam","date":"2028-09-18","time":"14:30","timing":"exact"}"#
        let usages: [ModelProvider: [String: Any]] = [
            .deepseek: ["prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120, "prompt_cache_hit_tokens": 40],
            .qwen: ["prompt_tokens": 200, "completion_tokens": 30, "prompt_tokens_details": ["cached_tokens": 0]],
            .kimi: ["prompt_tokens": 300, "completion_tokens": 40, "cached_tokens": 90],
            .glm: ["prompt_tokens": 400, "completion_tokens": 50, "prompt_tokens_details": ["cached_tokens": 200]]
        ]
        for provider in [ModelProvider.deepseek, .qwen, .kimi, .glm] {
            let config = provider.preset
            let draft = try await MailModel.recognize(capture, configuration: config, bypassCache: true, credential: "fixture-credential", ledger: ledger) { request in
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let expectedEndpoint = try config.endpoint
                assert(request.url == expectedEndpoint && request.httpMethod == "POST")
                assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-credential")
                assert(body["model"] as? String == config.model)
                if provider == .qwen { assert(body["enable_thinking"] as? Bool == false && body["thinking"] == nil) }
                else { assert((body["thinking"] as? [String: String])?["type"] == "disabled" && body["enable_thinking"] == nil) }
                if provider == .kimi { assert(body["temperature"] == nil && body["response_format"] == nil) }
                let response: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": content]]], "usage": usages[provider]!]
                return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            assert(draft.company == "虚构科技" && draft.time == "14:30")
        }
        let config = ModelProvider.deepseek.preset
        _ = try await MailModel.recognize(capture, configuration: config, credential: "fixture", ledger: ledger) { _ in
            fatalError("Local reuse must not make an HTTP request")
        }
        var records = try await ledger.snapshot()
        assert(records.count == 5 && records.last?.status == .local)
        var summary = ModelUsageSummary(records: records)
        assert(summary.sum(\.input) == 1000 && summary.sum(\.output) == 140 && summary.sum(\.total) == 1140)
        assert(summary.cacheReported.count == 4 && summary.cacheRate == 0.33 && summary.localCount == 1)
        // A parse failure still records billable usage exactly once.
        do {
            _ = try await MailModel.recognize(capture, configuration: config, bypassCache: true, credential: "fixture", ledger: ledger) { request in
                let response: [String: Any] = ["choices": [["finish_reason": "length", "message": ["content": "partial"]]], "usage": ["prompt_tokens": 50, "completion_tokens": 2000]]
                return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            fatalError("Truncated output must fail")
        } catch {}
        records = try await ledger.snapshot(); summary = .init(records: records)
        assert(records.count == 6 && records.last?.status == .failure && records.last?.tokens.output == 2000)
        assert(summary.cacheRate == 0.33 && summary.cacheReported.count == 4)
        do {
            _ = try await MailModel.recognize(capture, configuration: config, bypassCache: true, credential: "fixture", ledger: ledger) { _ in throw URLError(.timedOut) }
            fatalError("Timeout must fail")
        } catch {}
        records = try await ledger.snapshot()
        assert(records.count == 7 && records.last?.tokens.total == nil)
        // Tests bypass the local mail cache, even for identical text.
        _ = try await MailModel.recognize(capture, configuration: config, credential: "fixture", purpose: .test, ledger: ledger) { request in
            let response: [String: Any] = ["choices": [["message": ["content": content]]]]
            return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        records = try await ledger.snapshot(); assert(records.last?.purpose == .test && records.last?.status == .success)
        let missing = ModelTokenUsage.parse(["prompt_tokens": true, "completion_tokens": -1, "cached_tokens": 0.5])
        assert(missing.input == nil && missing.output == nil && missing.cached == nil)
        assert(ModelTokenUsage.parse(["prompt_tokens": 10, "cached_tokens": 11]).cached == nil)
        assert(ModelTokenUsage.parse(["prompt_tokens": 10, "cached_tokens": 0]).cached == 0)
        let generic = ModelConfiguration(baseURL: "https://example.com/custom/v2/chat/completions/", model: "some-model", jsonOutput: false)
        let endpoint = try generic.endpoint
        assert(endpoint.absoluteString == "https://example.com/custom/v2/chat/completions")
        assert(MailModel.requestBody(capture, configuration: generic)["thinking"] == nil)
        assert(MailModel.requestBody(capture, configuration: generic)["response_format"] == nil)
        for invalid in ["http://example.com", "https://example.com/?key=fixture", "https://user:password@example.com"] {
            do { _ = try ModelConfiguration(baseURL: invalid, model: "example").endpoint; fatalError("Unsafe URL accepted") } catch {}
        }
        let serialized = try String(contentsOf: directory.appendingPathComponent("usage.json"))
        assert(!serialized.contains("fixture-credential") && !serialized.contains("虚构科技") && !serialized.contains("chat/completions"))
        // Independent ledger instances must merge rather than overwrite one another.
        let second = ModelUsageLedger(url: directory.appendingPathComponent("usage.json"))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<40 {
                group.addTask { try await (i % 2 == 0 ? ledger : second).append(.init(configuration: config, purpose: .test, status: .local)) }
            }
            try await group.waitForAll()
        }
        records = try await ledger.snapshot(); assert(records.count == 48)
        let brokenURL = directory.appendingPathComponent("broken.json")
        let original = Data("not-valid-json".utf8); try original.write(to: brokenURL)
        let broken = ModelUsageLedger(url: brokenURL)
        do { try await broken.append(.init(configuration: config, purpose: .test, status: .success)); fatalError("Corruption must be preserved") } catch {}
        let preserved = try Data(contentsOf: brokenURL); assert(preserved == original)
        print("PASS: 4 provider transports, token/cache semantics, local reuse, failed-call accounting, test isolation, credential/body exclusion, concurrent ledgers, corrupt-file preservation")
    }
}
