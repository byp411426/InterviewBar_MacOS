import SwiftUI
import WidgetKit

struct RecruitmentEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}
struct RecruitmentProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecruitmentEntry { RecruitmentEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (RecruitmentEntry) -> Void) { completion(RecruitmentEntry(date: .now, snapshot: load())) }
    func load() -> WidgetSnapshot? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "InterviewBarWidgetGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: container.appendingPathComponent("widget-snapshot.json")) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecruitmentEntry>) -> Void) {
        let now = Date(), snapshot = load(), until = Date().addingTimeInterval(3600 * 6)
        var times = [now]
        times += (snapshot?.upcoming ?? []).filter { $0.date > now && $0.date < until }.map { $0.date.addingTimeInterval(1) }
        times += (1...12).map { now.addingTimeInterval(Double($0) * 1800) }
        let entries = Set(times).sorted().map { RecruitmentEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(until)))
    }
}
struct ReminderWidgetContent: View {
    let entry: RecruitmentEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("最近安排", systemImage: "calendar.badge.clock").font(.caption).foregroundStyle(.secondary)
            if let snapshot = entry.snapshot {
                if let next = snapshot.next(at: entry.date) {
                    Text(next.company).font(.title3.bold()).lineLimit(1).privacySensitive()
                    Text(timerInterval: entry.date...next.date, countsDown: true).font(.system(size: 27, weight: .medium, design: .monospaced)).minimumScaleFactor(0.6)
                    Text(next.kind + (next.isDeadline ? " · 截止" : " · 开始")).font(.caption)
                    Text(next.date, format: .dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))).font(.caption2).foregroundStyle(.secondary)
                } else { Text("暂时没有新安排").font(.headline); Text("打开日程，记录下一次机会。").font(.caption).foregroundStyle(.secondary) }
            } else { Text("打开面试日程同步").font(.headline); Text("完成首次启动后，安排会显示在这里。").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
struct StatisticsWidgetContent: View {
    let entry: RecruitmentEntry
    private let kinds = ["面试", "笔试", "测评", "AI面试"]
    private let colors: [Color] = [.mint, .orange, .blue, .purple]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("本周统计", systemImage: "chart.bar.xaxis").font(.caption).foregroundStyle(.secondary)
            if let snapshot = entry.snapshot {
                let counts = kinds.map { snapshot.count($0, at: entry.date) }
                Text("\(counts.reduce(0, +)) 次已完成").font(.title3.bold())
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(kinds.indices, id: \.self) { i in
                        VStack(spacing: 5) {
                            Text("\(counts[i])").font(.system(.caption, design: .monospaced).bold())
                            RoundedRectangle(cornerRadius: 3).fill(colors[i]).frame(height: max(3, CGFloat(counts[i]) / CGFloat(max(counts.max() ?? 1, 1)) * 20))
                            Text(kinds[i]).font(.system(size: 10))
                        }.frame(maxWidth: .infinity)
                    }
                }
                Text("周一至周日 · 按安排日期").font(.system(size: 10)).foregroundStyle(.secondary)
            } else { Text("打开面试日程同步").font(.headline); Text("你确认完成的经历，会慢慢汇成这一周。").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
struct InterviewReminderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InterviewBar.Reminder", provider: RecruitmentProvider()) { entry in
            ReminderWidgetContent(entry: entry)
                .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
                .containerBackground(for: .widget) { Color.mint.opacity(0.10) }
                .widgetURL(URL(string: "interviewbar://next"))
        }.configurationDisplayName("最近安排").description("下一次面试、笔试、测评或 AI 面试倒计时。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct InterviewStatisticsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InterviewBar.Statistics", provider: RecruitmentProvider()) { entry in
            StatisticsWidgetContent(entry: entry)
                .containerBackground(for: .widget) { Color.blue.opacity(0.09) }
                .widgetURL(URL(string: "interviewbar://journey"))
        }.configurationDisplayName("本周统计").description("看看本周完成了多少次面试、笔试、测评和 AI 面试。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
@main struct InterviewBarWidgetBundle: WidgetBundle {
    var body: some Widget { InterviewReminderWidget(); InterviewStatisticsWidget() }
}
