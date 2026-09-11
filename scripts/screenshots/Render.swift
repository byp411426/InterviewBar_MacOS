import AppKit
import SwiftUI

// Documentation-only fixtures. This renderer never opens the personal data directory,
// reads Keychain credentials, sends mail, or invokes a model service.
@MainActor enum DocumentationFixtures {
    static let config = ModelProvider.deepseek.preset
    static let mail = """
    同学你好：

    恭喜你通过星河科技校园招聘简历筛选！现邀请你参加 Java 开发工程师岗位的二面。

    面试日期：2026 年 9 月 18 日（周五）
    面试时间：14:30（北京时间）
    面试形式：在线视频面试
    会议号：123 456 789
    面试链接：https://example.com/interview

    请提前 10 分钟检查摄像头、麦克风和网络。
    预计面试时长约 45 分钟。

    星河科技校园招聘团队
    （操作演示邮件，非真实招聘通知）
    """
    static let fields = #"{"company":"星河科技","role":"Java 开发工程师","round":"二面","kind":"interview","date":"2026-09-18","time":"14:30","timing":"exact","timeNote":"2026年9月18日14:30，北京时间","isDeadline":false,"rejected":false,"location":"在线视频面试 · 会议号 123 456 789","link":"https://example.com/interview","warnings":[]}"#
    static var tab = 0
    static var usage: [ModelUsageRecord] {
        let inputs = [820, 940, 1050, 780], outputs = [112, 126, 140, 108], cached = [512, 640, 768, 0]
        var records: [ModelUsageRecord] = []
        for i in 0..<4 {
            var row = ModelUsageRecord(configuration: config, purpose: i == 0 ? .test : .mail, status: .success,
                seconds: [1.1, 0.9, 1.2, 1.0][i], httpStatus: 200,
                tokens: .init(input: inputs[i], output: outputs[i], total: inputs[i] + outputs[i], cached: cached[i]))
            row.date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(10 * 3600 + i * 1200))
            records.append(row)
        }
        var reused = ModelUsageRecord(configuration: config, purpose: .mail, status: .local)
        reused.date = records.last!.date.addingTimeInterval(600); records.append(reused)
        return records
    }
}

@main struct RenderDocumentation {
    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: .aqua)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("interviewbar-docs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = EventStore(directory: temporary, notificationsAllowed: false)
        store.now = Date()
        let companies = ["星河科技", "青禾软件", "云帆信息", "远山智能"]
        for week in 0..<8 {
            for (index, kind) in EventKind.allCases.enumerated() {
                let count = [1, 2, 1, 0, 2, 3, 2, 1][week] + ((week + index) % 3 == 0 ? 1 : 0)
                for offset in 0..<count {
                    store.save(InterviewEvent(company: companies[index], role: "软件开发工程师", kind: kind,
                        date: Calendar.current.date(byAdding: .day, value: -(7 - week) * 7 - offset, to: store.now)!, status: .completed))
                }
            }
        }
        await capture(ModelSettingsView(), name: "ai-configuration", size: NSSize(width: 740, height: 660), destination: destination)
        DocumentationFixtures.tab = 1
        await capture(ModelSettingsView(), name: "ai-usage", size: NSSize(width: 740, height: 660), destination: destination)
        let mailStore = EventStore(directory: temporary.appendingPathComponent("mail"), notificationsAllowed: false)
        await capture(MailImportView(store: mailStore, capture: MailCapture(text: DocumentationFixtures.mail), close: {}),
            name: "mail-recognition", size: NSSize(width: 860, height: 670), destination: destination)
        await capture(JourneyView(store: store, edit: { _ in }), name: "journey-statistics", size: NSSize(width: 1000, height: 820), destination: destination)
    }
    @MainActor static func capture<V: View>(_ view: V, name: String, size: NSSize, destination: URL) async {
        let hosting = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: "zh_CN")).environment(\.timeZone, shanghai).environment(\.controlActiveState, .key).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 600_000_000)
        hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("Cannot render " + name) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode " + name) }
        do { try png.write(to: destination.appendingPathComponent(name + ".png")); print("Rendered " + name) }
        catch { fatalError(error.localizedDescription) }
        window.contentView = nil; window.close()
    }
}
