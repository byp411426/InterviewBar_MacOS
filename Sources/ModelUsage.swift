import Foundation
import CoreFoundation
import Darwin

struct ModelTokenUsage: Codable, Equatable {
    var input: Int?
    var output: Int?
    var total: Int?
    var cached: Int?
    static func parse(_ value: Any?) -> ModelTokenUsage {
        let fields = value as? [String: Any] ?? [:]
        func count(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue >= 0, number.doubleValue < 1e12,
                  number.doubleValue.rounded(.down) == number.doubleValue else { return nil }
            return number.intValue
        }
        let input = count(fields["prompt_tokens"]), output = count(fields["completion_tokens"])
        let details = fields["prompt_tokens_details"] as? [String: Any]
        var cached = count(fields["prompt_cache_hit_tokens"]) ?? count(details?["cached_tokens"]) ?? count(fields["cached_tokens"])
        if let input, let hits = cached, hits > input { cached = nil }
        return .init(input: input, output: output,
            total: count(fields["total_tokens"]) ?? (input.flatMap { i in output.map { i + $0 } }), cached: cached)
    }
}

enum ModelCallPurpose: String, Codable, CaseIterable { case mail = "邮件识别", test = "连接测试" }
enum ModelCallStatus: String, Codable { case success = "成功", failure = "失败", cancelled = "已取消", local = "本机复用" }

struct ModelUsageRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var host: String
    var model: String
    var purpose: ModelCallPurpose
    var status: ModelCallStatus
    var seconds: Double
    var httpStatus: Int?
    var tokens: ModelTokenUsage
    var forced: Bool
    init(configuration: ModelConfiguration, purpose: ModelCallPurpose, status: ModelCallStatus,
         seconds: Double = 0, httpStatus: Int? = nil, tokens: ModelTokenUsage = .parse(nil), forced: Bool = false) {
        host = (try? configuration.endpoint.host) ?? "未知服务"
        model = configuration.model; self.purpose = purpose; self.status = status
        self.seconds = seconds; self.httpStatus = httpStatus; self.tokens = tokens; self.forced = forced
    }
}

struct ModelUsageSummary {
    let records: [ModelUsageRecord]
    var network: [ModelUsageRecord] { records.filter { $0.status != .local } }
    func sum(_ key: KeyPath<ModelTokenUsage, Int?>) -> Int? {
        let values = network.compactMap { $0.tokens[keyPath: key] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    var cacheReported: [ModelUsageRecord] { network.filter { $0.tokens.cached != nil && $0.tokens.input != nil } }
    var cacheRate: Double? {
        let denominator = cacheReported.reduce(0) { $0 + ($1.tokens.input ?? 0) }
        guard denominator > 0 else { return nil }
        return Double(cacheReported.reduce(0) { $0 + ($1.tokens.cached ?? 0) }) / Double(denominator)
    }
    var localCount: Int { records.filter { $0.status == .local }.count }
}

// Contains accounting metadata only. Never persist mail, credentials, URLs with paths,
// request bodies, responses, or arbitrary provider error text.
actor ModelUsageLedger {
    static let shared = ModelUsageLedger(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("InterviewBar/model-usage.json"))
    let url: URL
    private(set) var writeWarning = ""
    init(url: URL) { self.url = url }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path + ".lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw DataError.invalid("用量记录暂时无法打开。") }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw DataError.invalid("用量记录正忙。") }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
    private func readUnlocked() throws -> [ModelUsageRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([ModelUsageRecord].self, from: Data(contentsOf: url)) }
        catch { throw DataError.invalid("用量文件无法读取，已保留原文件；不会覆盖历史数据。") }
    }
    func snapshot() throws -> [ModelUsageRecord] { try locked { try readUnlocked() } }
    func append(_ record: ModelUsageRecord) throws {
        do { try locked {
            var records = try readUnlocked(); records.append(record)
            records = Array(records.suffix(10_000))
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        writeWarning = ""
        } catch {
            writeWarning = "部分调用用量未能保存，当前统计可能不完整。请检查数据目录的权限与剩余空间。"
            throw error
        }
    }
}
