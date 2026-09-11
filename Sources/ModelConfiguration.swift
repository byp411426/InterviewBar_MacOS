import Foundation

enum ModelProvider: String, CaseIterable, Codable, Identifiable {
    case deepseek, qwen, kimi, glm, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .deepseek: return "DeepSeek · 推荐"; case .qwen: return "千问 · 百炼"; case .kimi: return "Kimi"; case .glm: return "GLM · 智谱"; case .custom: return "自定义兼容服务" }
    }
    var preset: ModelConfiguration {
        switch self {
        case .deepseek: return .init(baseURL: "https://api.deepseek.com", model: "deepseek-flash", provider: self)
        case .qwen: return .init(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", provider: self)
        case .kimi: return .init(baseURL: "https://api.moonshot.cn/v1", model: "kimi-k2.6", provider: self, jsonOutput: false)
        case .glm: return .init(baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4.7-flash", provider: self)
        case .custom: return .init(baseURL: "", model: "", provider: self, jsonOutput: false)
        }
    }
    var saved: ModelConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "modelPreset." + rawValue), let value = try? JSONDecoder().decode(ModelConfiguration.self, from: data) else { return preset }
        return value
    }
}

extension Notification.Name { static let modelConfigurationChanged = Notification.Name("modelConfigurationChanged") }

struct ModelConfiguration: Codable {
    var baseURL: String
    var model: String
    var provider: ModelProvider = .custom
    var jsonOutput: Bool = true
    static var current: ModelConfiguration {
        ModelConfiguration(baseURL: UserDefaults.standard.string(forKey: "mailModelBaseURL") ?? "https://api.deepseek.com",
            model: UserDefaults.standard.string(forKey: "mailModelName") ?? "deepseek-flash",
            provider: ModelProvider(rawValue: UserDefaults.standard.string(forKey: "mailModelProvider") ?? "deepseek") ?? .custom,
            jsonOutput: UserDefaults.standard.object(forKey: "mailModelJSON") as? Bool ?? true)
    }
    static var enabled: Bool { UserDefaults.standard.object(forKey: "mailModelEnabled") as? Bool ?? true }
    static var isConfigured: Bool {
        // Existing versions saved the URL only after saving/reading a credential.
        UserDefaults.standard.bool(forKey: "mailModelConfigured") || UserDefaults.standard.string(forKey: "mailModelBaseURL") != nil
    }
    var adapter: ModelProvider {
        if provider != .custom { return provider }
        let name = model.lowercased()
        if name.hasPrefix("deepseek") { return .deepseek }
        if name.hasPrefix("qwen") { return .qwen }
        if name.hasPrefix("kimi") { return .kimi }
        if name.hasPrefix("glm") { return .glm }
        return .custom
    }
    var endpoint: URL {
        get throws {
            guard var url = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw DataError.invalid("请填写 API 的 HTTPS 地址，不要填写登录平台网址、密钥或查询参数。") }
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.isEmpty { url.path = "/v1/chat/completions" }
            else { url.path = "/" + path + (path.hasSuffix("chat/completions") ? "" : "/chat/completions") }
            guard let endpoint = url.url else { throw DataError.invalid("模型地址无效。") }
            return endpoint
        }
    }
    func validate() throws {
        _ = try endpoint
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DataError.invalid("请填写模型名称。") }
    }
    func persist() throws {
        try validate()
        if UserDefaults.standard.object(forKey: "legacyModelEndpoint") == nil {
            let legacy = UserDefaults.standard.string(forKey: "mailModelBaseURL") == nil ? "" : ((try? Self.current.endpoint.absoluteString) ?? "")
            UserDefaults.standard.set(legacy, forKey: "legacyModelEndpoint")
        }
        UserDefaults.standard.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "mailModelBaseURL")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "mailModelName")
        UserDefaults.standard.set(provider.rawValue, forKey: "mailModelProvider")
        UserDefaults.standard.set(jsonOutput, forKey: "mailModelJSON")
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "modelPreset." + provider.rawValue)
    }
}
