import SwiftUI
import Charts

private extension EventKind {
    var chartColor: Color {
        switch self {
        case .interview: Color(red: 0.16, green: 0.76, blue: 0.62)
        case .exam: Color(red: 1, green: 0.76, blue: 0.20)
        case .assessment: Color(red: 0.40, green: 0.66, blue: 1)
        case .aiInterview: Color(red: 0.90, green: 0.45, blue: 0.78)
        }
    }
}
struct JourneyView: View {
    @ObservedObject var store: EventStore
    let edit: (InterviewEvent?) -> Void
    var editUnscheduled: (UnscheduledEvent) -> Void = { _ in }
    @State private var kind = EventKindFilter.all
    @State private var quote = JourneyStats.nextEncouragement()
    @State private var metric = JourneyMetric.completed
    @State private var range = JourneyRange.eight
    @State private var page = "每周分布"
    @State private var selectedWeek: String?
    private let canvas = Color(red: 0.085, green: 0.085, blue: 0.10)
    var weeks: [JourneyChartWeek] { JourneyStats.chartWeeks(store.events, now: store.now, range: range, metric: metric) }
    var events: [InterviewEvent] { weeks.flatMap(\.events).filter { kind.matches($0.kind) } }
    var kinds: [EventKind] { EventKind.allCases.filter { kind.matches($0) } }
    var selected: JourneyChartWeek? { weeks.first { $0.id == selectedWeek } }
    var maximum: Int {
        if page == "累计趋势" { return max(1, kinds.map { type in events.filter { $0.kind == type }.count }.max() ?? 0) }
        return max(1, weeks.flatMap { week in kinds.map { week.count($0) } }.max() ?? 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    controls
                    totals
                    if !store.unscheduled.isEmpty {
                        DisclosureGroup("时间或信息待补记录 · 已完成 \(store.unscheduled.filter { $0.recordStatus == .completed }.count) 项") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("以下记录单独保留，不计入按周图表，也不受周范围筛选影响。修正为明确的安排时间后再归入对应周。").font(.system(size: 11)).foregroundStyle(.secondary)
                                ForEach(store.unscheduled.filter { kind.matches($0.kind) && (metric == .scheduled || $0.recordStatus == .completed) }) { item in
                                    HStack {
                                        Text(item.displayCompany + " · " + (item.kind?.rawValue ?? "类型待确认"))
                                        Spacer()
                                        Text(item.statusLabel).foregroundStyle(.secondary)
                                        Button("修正信息") { editUnscheduled(item) }
                                    }.font(.system(size: 12))
                                }
                            }.padding(.top, 8)
                        }
                    }
                    if page == "记录明细" { timeline }
                    else { chartSection }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "leaf").foregroundStyle(EventKind.interview.chartColor)
                        Text(quote).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 10)
                        Button("换一句") { quote = JourneyStats.nextEncouragement(excluding: quote) }.buttonStyle(.plain).foregroundStyle(.white)
                    }.padding(.top, 4)
                }.padding(28)
            }
            Divider()
            Text("北京时间 · 周一至周日，按安排日期归周。已完成需手动确认；全部安排包含待办、取消和未通过，不等于参加次数。\(store.unscheduled.count) 项时间或信息待补记录单独保留，未计入图表。")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 14).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 740, minHeight: 560).background(canvas).preferredColorScheme(.dark)
        .onChange(of: range) { _ in selectedWeek = nil }
        .onChange(of: metric) { _ in selectedWeek = nil }
        .alert("保存提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 24) {
            Label("我的秋招之旅", systemImage: "chart.bar.xaxis").font(.system(size: 22, weight: .semibold))
            Spacer()
            ForEach(["每周分布", "累计趋势", "记录明细"], id: \.self) { value in
                Button { page = value } label: {
                    VStack(spacing: 10) {
                        Text(value).font(.system(size: 14, weight: page == value ? .semibold : .regular)).foregroundStyle(page == value ? .white : .secondary)
                        Rectangle().fill(page == value ? EventKind.interview.chartColor : .clear).frame(height: 2)
                    }.padding(.top, 12)
                }.buttonStyle(.plain).accessibilityAddTraits(page == value ? .isSelected : [])
            }
        }.padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 4)
    }
    private var controls: some View {
        HStack(spacing: 16) {
            Picker("统计", selection: $metric) { ForEach(JourneyMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 180)
            Picker("时间", selection: $range) { ForEach(JourneyRange.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 175)
            Picker("类型", selection: $kind) { ForEach(EventKindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 155)
            Spacer(minLength: 0)
        }
    }
    private var totals: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric == .completed ? "已完成次数" : "已记录安排").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(events.count)").font(.system(size: 36, weight: .medium, design: .monospaced))
                    Text(metric == .completed ? "次" : "项").foregroundStyle(.secondary)
                }
            }.frame(minWidth: 140, alignment: .leading)
            ForEach(kinds, id: \.self) { type in
                VStack(alignment: .leading, spacing: 9) {
                    Label(type.rawValue, systemImage: type.symbol).font(.system(size: 12)).foregroundStyle(type.chartColor)
                    Text("\(events.filter { $0.kind == type }.count)").font(.system(size: 25, weight: .medium, design: .monospaced))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(page == "每周分布" ? "每周\(metric.rawValue)分布" : "\(metric.rawValue)累计趋势").font(.system(size: 20, weight: .semibold))
                Spacer()
                if let first = weeks.first, let last = weeks.last {
                    Text(dateText(first.start, "yyyy.MM.dd") + " — " + dateText(last.end, "yyyy.MM.dd")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Text(page == "累计趋势" ? "从所选时间范围首周开始累计。点击图表选中一周，可查看该周记录。" : "横轴为每周起始日，纵轴为次数。点击柱状图所在周，可查看该周记录。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if events.isEmpty {
                HStack {
                    Image(systemName: "chart.bar").foregroundStyle(.secondary)
                    Text(metric == .completed ? "这个范围内还没有已完成记录。完成后可标记，也可以切换“全部安排”查看安排量。" : "这个范围内没有安排。未来周的安排可切换“全部时间”查看。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    chart.padding(.top, 10).frame(width: max(geometry.size.width - 2, CGFloat(weeks.count) * 88), height: 300)
                }
            }.frame(height: 315)
            HStack(spacing: 22) {
                ForEach(kinds, id: \.self) { type in
                    HStack(spacing: 6) { Rectangle().fill(type.chartColor).frame(width: 10, height: 10); Text(type.rawValue) }.font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            HStack {
                Picker("查看某周", selection: Binding(get: { selectedWeek ?? "" }, set: { selectedWeek = $0.isEmpty ? nil : $0 })) {
                    Text("选择一周查看记录").tag("")
                    ForEach(weeks) { week in Text(dateText(week.start, "yyyy.MM.dd") + " — " + dateText(week.end, "MM.dd")).tag(week.id) }
                }.frame(maxWidth: 340)
                Spacer()
                Button("全部记录明细") { page = "记录明细" }.buttonStyle(.plain).foregroundStyle(EventKind.interview.chartColor)
            }
            if let selected {
                let records = selected.events.filter { kind.matches($0.kind) }
                Text("本周\(metric.rawValue) \(records.count) 项").font(.system(size: 13, weight: .medium))
                if records.isEmpty { Text("这一周没有符合当前筛选的记录。").font(.caption).foregroundStyle(.secondary) }
                ForEach(records) { row($0) }
            }
        }
    }
    private struct ChartPoint: Identifiable {
        let week: String
        let kind: EventKind
        let count: Int
        var id: String { week + kind.rawValue }
    }
    private var points: [ChartPoint] {
        var totals: [String: Int] = [:]
        return weeks.flatMap { week in kinds.map { type in
            let count = week.count(type)
            totals[type.rawValue, default: 0] += count
            return ChartPoint(week: week.id, kind: type, count: page == "累计趋势" ? totals[type.rawValue]! : count)
        } }
    }
    @ChartContentBuilder private var marks: some ChartContent {
        if page == "每周分布" {
            ForEach(points) { point in
                BarMark(x: .value("周", point.week), y: .value("次数", point.count))
                    .position(by: .value("类型", point.kind.rawValue))
                    .foregroundStyle(by: .value("类型", point.kind.rawValue))
                    .annotation(position: .top) { if point.count > 0 { Text("\(point.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(point.kind.chartColor) } }
                    .accessibilityLabel(point.week + "起的一周，" + point.kind.rawValue)
                    .accessibilityValue("\(point.count)次")
            }
        } else {
            ForEach(points) { point in
                LineMark(x: .value("周", point.week), y: .value("累计次数", point.count))
                    .foregroundStyle(by: .value("类型", point.kind.rawValue)).symbol(by: .value("类型", point.kind.rawValue))
            }
        }
        if let selectedWeek, weeks.contains(where: { $0.id == selectedWeek }) {
            RuleMark(x: .value("选中周", selectedWeek)).foregroundStyle(Color.white.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
        }
    }
    private var chart: some View {
        Chart { marks }
        .chartForegroundStyleScale(domain: EventKind.allCases.map(\.rawValue), range: EventKind.allCases.map(\.chartColor))
        .chartLegend(.hidden)
        .chartYScale(domain: 0...(maximum + max(1, maximum / 5)))
        .chartXScale(domain: weeks.map(\.id))
        .chartXAxis { AxisMarks(values: weeks.map(\.id)) { value in
            AxisTick()
            AxisValueLabel { if let id = value.as(String.self), let week = weeks.first(where: { $0.id == id }) { Text(week.label).font(.system(size: 11, design: .monospaced)) } }
        } }
        .chartYAxis { AxisMarks(position: .leading, values: Array(stride(from: 0, through: maximum + max(1, maximum / 5), by: max(1, Int(ceil(Double(maximum) / 5)))))) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.09)); AxisValueLabel() } }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    let frame = geometry[proxy.plotAreaFrame]
                    guard frame.contains(value.location), let id: String = proxy.value(atX: value.location.x - frame.minX) else { return }
                    selectedWeek = id
                })
            }
        }
    }
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            if events.isEmpty { Text("没有符合筛选的记录。试试其他时间或统计范围。").foregroundStyle(.secondary) }
            ForEach(JourneyStats.weeks(events)) { week in
                Text(dateText(week.start, "yyyy.MM.dd") + " — " + dateText(week.end, "MM.dd") + " · \(week.events.count) 项").font(.system(size: 15, weight: .semibold, design: .monospaced)).padding(.top, 8)
                ForEach(week.events) { row($0) }
            }
        }
    }
    private func row(_ event: InterviewEvent) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Text(dateText(event.date, "MM/dd HH:mm")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 95, alignment: .leading)
                Rectangle().fill(event.kind.chartColor).frame(width: 3, height: 27)
                VStack(alignment: .leading, spacing: 4) {
                    Button(event.company) { edit(event) }.buttonStyle(.plain).font(.system(size: 14, weight: .medium))
                    Text(event.kindLabel + (event.isDeadline ? " · 截止" : "") + (event.role.isEmpty ? "" : " · " + event.role)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("编辑安排") { edit(event) }
                    Button("标记已完成") { store.setStatus(event, .completed) }
                    Button("恢复待办") { store.setStatus(event, .pending) }
                    Button("取消安排") { store.setStatus(event, .cancelled) }
                } label: { Text(event.overdue(at: store.now) ? "已过时间 · 待确认" : event.status.rawValue) }.menuStyle(.borderlessButton).fixedSize()
            }
            Divider()
        }
    }
}
