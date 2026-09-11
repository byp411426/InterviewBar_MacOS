import SwiftUI

struct ModelSettingsView: View {
    @State private var configuration = ModelConfiguration.current
    @State private var key = ""
    @State private var enabled = ModelConfiguration.enabled
    @State private var message = ""
    @State private var busy = false
    @State private var testTask: Task<Void, Never>?
    @State private var selectedTab = 0
    var close: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI 服务与用量").font(.system(size: 25, weight: .semibold))
                    Text("配置一次，复制邮件后即可识别").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { Button("停止测试") { testTask?.cancel() } }
                if let close { Button("返回邮件", action: close) }
            }
            Picker("页面", selection: $selectedTab) {
                Text("服务配置").tag(0); Text("用量统计").tag(1)
            }.pickerStyle(.segmented)
            if selectedTab == 0 { settings } else { ModelUsageView() }
        }.padding(24).frame(width: 740, height: 660)
            .onDisappear { testTask?.cancel() }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1  选择服务商").font(.headline)
            Picker("服务商", selection: Binding(get: { configuration.provider }, set: {
                configuration = $0.saved; key = ""; message = "已填入配置，请检查模型名与密钥。"
            })) {
                ForEach(ModelProvider.allCases) { Text($0.title).tag($0) }
            }.labelsHidden()
            Text("推荐 DeepSeek 用于低成本邮件字段提取。预设可修改；千问不同地域的地址与密钥不能混用。").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("2  填写连接信息").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                SwiftUI.GridRow { Text("API 地址"); TextField("https://…/v1", text: $configuration.baseURL) }
                SwiftUI.GridRow { Text("模型名称"); TextField("填写 API 模型名，不是网页显示名称", text: $configuration.model) }
                SwiftUI.GridRow { Text("API 密钥"); SecureField("首次使用请填写；相同地址已有密钥可留空", text: $key) }
            }.textFieldStyle(.roundedBorder)
            Text("自定义服务需兼容 OpenAI Chat Completions。不会自动转换 Claude、Gemini 等专用协议。").font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle("要求 JSON 输出（接口报不支持时可关闭）", isOn: $configuration.jsonOutput).font(.system(size: 12))
            Toggle("新邮件默认使用 AI 识别", isOn: $enabled)
            Text("3  测试并保存").font(.headline)
            Text("测试只发送一段虚构招聘通知，也会消耗少量 Token。保存后回到邮件：复制正文 → 粘贴 → AI 识别 → 核对 → 保存安排。").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button(busy ? "正在测试…" : "测试连接") { testConnection() }.disabled(busy)
                Button("保存并使用") { save() }.buttonStyle(.borderedProminent).tint(accent).disabled(busy)
                if busy { ProgressView().controlSize(.small) }
            }
            if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(accent).textSelection(.enabled) }
            Spacer(minLength: 0)
            Divider()
            Text("密钥按 API 地址保存在本机钥匙串。识别时只发送你粘贴的正文；用量记录不保存正文或密钥。费用由服务商结算。").font(.system(size: 11)).foregroundStyle(.secondary)
        }.disabled(busy)
    }

    private func save() {
        do {
            try configuration.validate()
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try ModelKeychain.save(key, configuration: configuration) }
            if enabled { _ = try ModelKeychain.read(configuration: configuration) }
            try configuration.persist()
            UserDefaults.standard.set(enabled, forKey: "mailModelEnabled")
            UserDefaults.standard.set(enabled, forKey: "mailModelConfigured")
            key = ""; message = "已保存。回到邮件窗口，点击“重新识别”开始。"
            Task { await MailModelCache.shared.clear() }
            NotificationCenter.default.post(name: .modelConfigurationChanged, object: nil)
        } catch { message = error.localizedDescription }
    }
    private func testConnection() {
        let config = configuration
        let override = key.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true; message = "正在验证连接与字段提取，请稍候…"
        testTask = Task { @MainActor in
            defer { busy = false }
            do {
                let start = Date()
                let result = try await MailModel.recognize(MailCapture(text: "示例科技邀请参加笔试，时间为2028年9月18日14:30，地点线上。"),
                    configuration: config, bypassCache: true, credential: override.isEmpty ? nil : override, purpose: .test)
                guard !Task.isCancelled else { return }
                if result.company.isEmpty || result.kind != .exam || result.day != "2028-09-18" || result.time != "14:30" {
                    message = "接口已连接，但样例字段提取不完整。可换模型重测；用量已记录。"
                } else { message = String(format: "连接与识别正常，用时 %.1f 秒。请点击“保存并使用”。用量可在统计页查看。", Date().timeIntervalSince(start)) }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
}
