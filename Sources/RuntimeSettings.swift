import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class RuntimeSettings: ObservableObject {
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginMessage = ""
    @Published private(set) var requiresApproval = false
    @Published var error: String?

    func refresh() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
        switch status {
        case .enabled: loginMessage = "已开启 · 下次登录 Mac 时自动启动"
        case .requiresApproval: loginMessage = "请在系统登录项中允许“面试日程”"
        case .notRegistered: loginMessage = "未开启 · 可随时从“应用程序”打开"
        case .notFound: loginMessage = "系统未找到应用，请从安装位置重新打开"
        @unknown default: loginMessage = "暂时无法确认登录项状态"
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = "更改自动启动失败：\(error.localizedDescription)" }
        refresh()
    }
}

struct SettingsView: View {
    @ObservedObject var store: EventStore
    @ObservedObject var runtime: RuntimeSettings
    var resetPosition: () -> Void
    var export: () -> Void
    var quit: () -> Void
    var modelSettings: () -> Void
    var widgetSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置").font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 9) {
                Toggle("登录后自动启动", isOn: Binding(get: { runtime.loginEnabled }, set: { runtime.setLoginEnabled($0) }))
                    .toggleStyle(.switch)
                Text(runtime.loginMessage).font(.system(size: 12)).foregroundStyle(.secondary)
                if runtime.requiresApproval {
                    Button("打开系统登录项") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("关闭窗口不会退出。息屏、锁屏后继续驻留，亮屏时刷新菜单栏；关机后在下次登录时恢复。").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Label("菜单栏使用小图标", systemImage: "calendar.badge.clock")
                Text("悬停查看下一项，点击展开日程。按住 ⌘ 拖动图标可调整位置，应用会记住位置。").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("恢复到菜单栏右侧") { resetPosition() }
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Toggle("本机通知提醒", isOn: Binding(get: { store.remindersEnabled }, set: { if $0 { store.enableReminders() } else { store.disableReminders() } })).toggleStyle(.switch)
                Text(store.reminderMessage).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let error = runtime.error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack { Button("邮件识别模型设置…", action: modelSettings); Button("桌面小组件…", action: widgetSettings) }
            Spacer(minLength: 0)
            HStack {
                Button("导出 CSV", action: export)
                Button("打开数据目录") { NSWorkspace.shared.open(store.repository.url.deletingLastPathComponent()) }
                Spacer()
                Button("退出应用", action: quit)
            }.font(.system(size: 12))
        }.padding(26).frame(width: 510, height: 500)
            .onAppear { runtime.refresh() }
    }
}
