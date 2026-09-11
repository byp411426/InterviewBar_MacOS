import SwiftUI

struct ModelSettingsView: View {
    @State private var baseURL = ModelConfiguration.current.baseURL
    @State private var model = ModelConfiguration.current.model
    @State private var key = ""
    @State private var enabled = UserDefaults.standard.bool(forKey: "mailModelEnabled")
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("邮件识别模型").font(.system(size: 23, weight: .semibold))
            TextField("服务地址（HTTPS）", text: $baseURL)
            TextField("模型名称", text: $model)
            SecureField("API 密钥（已保存时可留空）", text: $key)
            Toggle("新邮件默认使用 AI 识别", isOn: $enabled)
            Text("AI 识别会将你选中或粘贴的正文发送给上面的服务。密钥按服务地址保存在本机钥匙串，不保存在浏览器扩展、日程文件或导出表格中。").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("日期、时刻和岗位等未知项会留空。识别结果需要核对后保存；没有明确时刻的安排不设置定时提醒。").font(.system(size: 12)).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.system(size: 12)) }
            Spacer()
            HStack { Spacer(); Button("保存模型设置") {
                do {
                    let config = ModelConfiguration(baseURL: baseURL, model: model)
                    if !key.isEmpty { try ModelKeychain.save(key, configuration: config) }
                    if enabled { _ = try ModelKeychain.read(configuration: config) }
                    try config.persist(); UserDefaults.standard.set(enabled, forKey: "mailModelEnabled")
                    key = ""; message = "设置已保存。回到邮件窗口点击“重新识别”即可。"
                } catch { message = error.localizedDescription }
            }.buttonStyle(.borderedProminent).tint(accent) }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 510, height: 400)
    }
}
