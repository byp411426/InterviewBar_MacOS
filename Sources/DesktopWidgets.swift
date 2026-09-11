import AppKit
import SwiftUI
import WidgetKit

enum DesktopWidgetKind: String, CaseIterable { case reminder = "最近安排", statistics = "本周统计" }

@MainActor final class DesktopWidgets: NSObject, ObservableObject, NSWindowDelegate {
    let store: EventStore
    var openJourney: () -> Void = {}
    var openEvent: (InterviewEvent?) -> Void = { _ in }
    @Published var reminder = UserDefaults.standard.bool(forKey: "desktopWidget.reminder")
    @Published var statistics = UserDefaults.standard.bool(forKey: "desktopWidget.statistics")
    @Published var floating = UserDefaults.standard.bool(forKey: "desktopWidget.floating")
    private var panels: [DesktopWidgetKind: NSPanel] = [:]
    private var previousSnapshot: Data?
    init(store: EventStore) { self.store = store; super.init() }
    func restore() {
        if reminder { show(.reminder) }
        if statistics { show(.statistics) }
    }
    func set(_ type: DesktopWidgetKind, enabled: Bool) {
        if type == .reminder { reminder = enabled } else { statistics = enabled }
        UserDefaults.standard.set(enabled, forKey: type == .reminder ? "desktopWidget.reminder" : "desktopWidget.statistics")
        if enabled { show(type) } else { panels[type]?.orderOut(nil) }
    }
    func setFloating(_ enabled: Bool) {
        floating = enabled; UserDefaults.standard.set(enabled, forKey: "desktopWidget.floating")
        for panel in panels.values { panel.level = level }
    }
    var level: NSWindow.Level { floating ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) }
    func show(_ type: DesktopWidgetKind) {
        if let panel = panels[type] { panel.orderFrontRegardless(); return }
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let panel = NSPanel(contentRect: NSRect(x: frame.minX + 30, y: frame.maxY - (type == .reminder ? 250 : 490), width: 330, height: 210), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = type.rawValue + " · 面试日程组件"
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 300, height: 200); panel.maxSize = NSSize(width: 520, height: 320)
        panel.setFrameAutosaveName("InterviewBar.Widget." + type.rawValue)
        panel.setFrameUsingName("InterviewBar.Widget." + type.rawValue)
        // Reconnect / monitor removal may leave a saved frame offscreen.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.setFrameOrigin(NSPoint(x: frame.minX + 30, y: frame.maxY - 250)) }
        panel.contentView = NSHostingView(rootView: DesktopWidgetView(store: store, kind: type, close: { [weak self] in self?.set(type, enabled: false) }, open: { [weak self] in
            guard let self else { return }
            if type == .statistics { openJourney() } else { openEvent(store.next) }
        }))
        panels[type] = panel; panel.orderFrontRegardless()
    }
    func publishSnapshot() {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "InterviewBarWidgetGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        // Compare underlying records, not updatedAt, to avoid requesting a timeline reload every timer tick.
        guard let signature = try? JSONEncoder().encode(store.events), signature != previousSnapshot else { return }
        do {
            let data = try JSONEncoder().encode(WidgetSnapshot.make(events: store.events, now: Date()))
            let file = container.appendingPathComponent("widget-snapshot.json")
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            previousSnapshot = signature
            WidgetCenter.shared.reloadAllTimelines()
        } catch { store.error = "原生小组件快照更新失败：" + error.localizedDescription }
    }
}
private struct GlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow
        view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
struct DesktopWidgetView: View {
    @ObservedObject var store: EventStore
    let kind: DesktopWidgetKind
    let close: () -> Void
    let open: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: kind == .reminder ? 1 : 30)) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(kind.rawValue, systemImage: kind == .reminder ? "calendar.badge.clock" : "chart.bar.xaxis").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 20, height: 20) }.buttonStyle(.plain).accessibilityLabel("隐藏" + kind.rawValue + "组件")
                }
                if kind == .reminder { reminder(now: context.date) } else { statistics(now: context.date) }
                Spacer(minLength: 0)
                HStack {
                    Text(kind == .reminder ? "北京时间 · 下一项待办" : "按安排日期归周 · 仅已完成").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: open) { Image(systemName: "arrow.up.right").frame(width: 24, height: 22) }.buttonStyle(.plain).accessibilityLabel(kind == .reminder ? "查看最近安排" : "打开统计图")
                }
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassMaterial()).background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
    }
    @ViewBuilder private func reminder(now: Date) -> some View {
        if let event = store.pending.first(where: { $0.date > now }) {
            Text(event.company).font(.system(size: 22, weight: .semibold)).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("还剩").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(timerInterval: now...event.date, countsDown: true).font(.system(size: 29, weight: .medium, design: .monospaced)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(event.kindLabel + " · " + dateText(event.date, "M/d HH:mm") + (event.isDeadline ? " 截止" : " 开始")).font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Text("暂时没有新安排").font(.system(size: 22, weight: .medium))
            Text("重要时间记下来，留一点空间给生活。").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func statistics(now: Date) -> some View {
        let snapshot = WidgetSnapshot.make(events: store.events, now: now)
        let counts = EventKind.allCases.map { snapshot.count($0.rawValue, at: now) }
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(counts.reduce(0, +))").font(.system(size: 35, weight: .medium, design: .monospaced))
                Text("次已完成").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 14) {
                ForEach(Array(EventKind.allCases.enumerated()), id: \.element) { i, type in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(counts[i])").font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(type.tint)
                        Text(type.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                        Capsule().fill(type.tint.opacity(0.65)).frame(height: 3)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
struct WidgetSettingsView: View {
    @ObservedObject var widgets: DesktopWidgets
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("桌面小组件").font(.system(size: 24, weight: .semibold))
            Text("两块可以独立摆放的玻璃面板，数据与日程实时联动。").foregroundStyle(.secondary)
            Toggle("显示最近安排", isOn: Binding(get: { widgets.reminder }, set: { widgets.set(.reminder, enabled: $0) }))
            Toggle("显示本周统计", isOn: Binding(get: { widgets.statistics }, set: { widgets.set(.statistics, enabled: $0) }))
            Divider()
            Toggle("置于其他窗口上方", isOn: Binding(get: { widgets.floating }, set: { widgets.setFloating($0) }))
            Text("关闭置顶时留在桌面层；开启后可在工作窗口上方查看。拖动空白处调整位置，拖边缘调整大小。显示状态和位置会记住。").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(Bundle.main.object(forInfoDictionaryKey: "InterviewBarWidgetGroup") != nil ? "原生扩展已随应用安装。打开系统“编辑小组件”，搜索面试日程；数据通过本机共享容器同步。" : "这是应用提供的桌面组件。系统“编辑小组件”中的原生版本需要另行签名安装 WidgetKit 扩展；当前临时签名安装包不提供该入口。").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }.padding(26).frame(width: 490, height: 370)
    }
}
