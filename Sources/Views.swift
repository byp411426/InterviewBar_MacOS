import SwiftUI
import AppKit

let accent = Color(red: 0.22, green: 0.40, blue: 0.32)
extension EventKind {
    var symbol: String { switch self { case .interview: "person.2"; case .exam: "pencil.line"; case .assessment: "checklist"; case .aiInterview: "video.badge.waveform" } }
    var tint: Color { switch self { case .interview: accent; case .exam: .orange; case .assessment: .blue; case .aiInterview: .purple } }
}
struct Dashboard: View {
    @ObservedObject var store: EventStore
    @ObservedObject var sizing: PanelSize
    var edit: (InterviewEvent?) -> Void
    var export: () -> Void
    var openWorkspace: () -> Void
    var openSettings: () -> Void
    var openJourney: () -> Void
    var importMail: () -> Void
    @State private var filter = "待办"
    @State private var search = ""
    @State private var kindFilter = EventKindFilter.all
    var typeEvents: [InterviewEvent] { store.events.filter { kindFilter.matches($0.kind) } }
    var typeUnscheduled: [UnscheduledEvent] { store.unscheduled.filter { kindFilter.matches($0.kind) } }
    var visibleUnscheduled: [UnscheduledEvent] { filter == "已完成" ? [] : typeUnscheduled.filter { search.isEmpty || ($0.company + $0.role).localizedCaseInsensitiveContains(search) } }
    var next: InterviewEvent? { typeEvents.filter { $0.status == .pending && $0.date >= store.now }.min { $0.date < $1.date } }
    var filtered: [InterviewEvent] {
        typeEvents.filter { event in
            (filter == "全部" || (filter == "待办" ? event.status == .pending : event.status == .completed)) &&
            (search.isEmpty || (event.company + event.role + event.notes).localizedCaseInsensitiveContains(search))
        }.sorted { $0.date < $1.date }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("面试日程").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(dateText(store.now, "M月d日 EEEE") + " · 北京时间").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { edit(nil) } label: { Image(systemName: "plus").font(.system(size: 18, weight: .medium)).frame(width: 34, height: 34) }
                    .buttonStyle(.plain).background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(accent).help("添加安排").accessibilityLabel("添加安排")
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
            if let next = next {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("下一项安排", systemImage: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text(countdown(next.date)).font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(accent)
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.company).font(.system(size: 21, weight: .semibold))
                        Text(next.kindLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    HStack {
                        Text(dateText(next.date, "M月d日 E HH:mm") + (next.isDeadline ? " 截止" : " 开始")).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("查看") { edit(next) }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    }
                }.padding(16).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
            }
            HStack(spacing: 0) {
                stat("待进行", typeEvents.filter { $0.status == .pending && $0.date >= store.now }.count)
                Divider().frame(height: 22)
                stat("待确认", typeEvents.filter { $0.status == .pending && $0.date < store.now }.count + typeUnscheduled.count)
                Divider().frame(height: 22)
                stat("已完成", typeEvents.filter { $0.status == .completed }.count)
            }.padding(.vertical, 16).padding(.horizontal, 12)
            HStack(spacing: 12) {
                Picker("筛选", selection: $filter) { ForEach(["待办", "已完成", "全部"], id: \.self) { Text($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 205)
                HStack(spacing: 5) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索公司", text: $search).textFieldStyle(.plain).font(.system(size: 11)) }.padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }.padding(.horizontal, 20).padding(.bottom, 9)
            Picker("类型筛选", selection: $kindFilter) {
                ForEach(EventKindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 9)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty && visibleUnscheduled.isEmpty {
                        VStack(spacing: 10) { Image(systemName: "calendar").font(.system(size: 25)); Text(search.isEmpty ? "这里还没有安排" : "没有找到匹配的记录"); Text("右上角 ＋ 随时添加").font(.system(size: 11)) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 36)
                    }
                    ForEach(filtered) { event in
                        EventRow(event: event, now: store.now, edit: { edit(event) }, status: { store.setStatus(event, $0) })
                        Divider().padding(.leading, 68)
                    }
                    if filter != "已完成" {
                        ForEach(visibleUnscheduled) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(item.displayCompany).font(.system(size: 13, weight: .semibold)); Spacer(); Text("时间待通知").font(.system(size: 10)).foregroundStyle(.orange) }
                                Text((item.kind?.rawValue ?? "类型待确认") + " · " + item.displayTime).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 22).padding(.vertical, 12)
                            Divider()
                        }
                    }
                }
            }.frame(maxHeight: .infinity)
            Divider()
            Button(action: importMail) {
                HStack { Label("粘贴识别邮件", systemImage: "doc.on.clipboard"); Spacer(); Text("⌘C 后点这里").foregroundStyle(.secondary) }.font(.system(size: 12, weight: .medium)).foregroundStyle(accent).padding(.horizontal, 22).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Divider()
            HStack {
                Button(action: openWorkspace) { Label("投递总表与日程", systemImage: "tablecells") }
                Spacer()
                Button(action: openJourney) { Label("秋招之旅", systemImage: "map") }
            }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(accent).padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            HStack {
                Image(systemName: "internaldrive").font(.system(size: 10))
                Text("仅保存在此 Mac").font(.system(size: 10))
                Spacer()
                Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).help("设置与导出").accessibilityLabel("设置与导出")
            }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 14)
        }.frame(width: sizing.size.width, height: sizing.size.height).background(Color(nsColor: .windowBackgroundColor))
            .overlay { PanelResizeEdges(sizing: sizing) }
            .alert("日程提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func stat(_ label: String, _ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(count)").font(.system(size: 20, weight: .medium, design: .rounded)); Text(label).font(.system(size: 10)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
    func countdown(_ date: Date) -> String {
        let seconds = date.timeIntervalSince(store.now)
        if seconds < 60 { return "即将开始" }
        if seconds < 3600 { return "还有 \(Int(seconds / 60)) 分钟" }
        if seconds < 86400 { return "还有 \(Int(seconds / 3600)) 小时" }
        return "还有 \(Int(seconds / 86400)) 天"
    }
}
struct EventRow: View {
    let event: InterviewEvent
    let now: Date
    let edit: () -> Void
    let status: (EventStatus) -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 3) {
                Text(dateText(event.date, "dd")).font(.system(size: 20, weight: .medium, design: .rounded))
                Text(dateText(event.date, "E")).font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 36)
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(event.company).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                        Text(event.kindLabel).font(.system(size: 9)).padding(.horizontal, 5).padding(.vertical, 2).background(event.kind.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(event.kind.tint)
                    }
                    Text(dateText(event.date, "M/d HH:mm") + (event.isDeadline ? " 截止" : "") + (event.role.isEmpty ? "" : " · " + event.role)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    if event.overdue(at: now) { Text("时间已过 · 等你确认结果").font(.system(size: 10)).foregroundStyle(.orange) }
                    else if event.status != .pending { Text(event.status.rawValue).font(.system(size: 10)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button("编辑安排", action: edit)
                if !event.link.isEmpty, let url = URL(string: event.link) { Button("打开链接") { NSWorkspace.shared.open(url) } }
                Divider()
                if event.status != .completed { Button("标记已完成") { status(.completed) } }
                if event.status != .pending { Button("恢复待办") { status(.pending) } }
                if event.status != .cancelled { Button("取消安排") { status(.cancelled) } }
            } label: { Image(systemName: "ellipsis").frame(width: 18, height: 24) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("\(event.company)操作")
        }.padding(.horizontal, 20).padding(.vertical, 13)
    }
}
struct EventEditor: View {
    @State var event: InterviewEvent
    let save: (InterviewEvent) -> Void
    let cancel: () -> Void
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: event.kind.symbol).font(.system(size: 23)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.company.isEmpty ? "下一次机会，记在这里。" : event.company).font(.system(size: 19, weight: .semibold))
                    Text("面试、笔试、测评、AI面试，一处安排。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 4)
            Form {
                TextField("公司 *", text: $event.company)
                TextField("岗位", text: $event.role)
                Picker("类型", selection: $event.kind) { ForEach(EventKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if event.kind == .interview {
                    TextField("面试轮次", text: Binding(get: { event.round ?? "" }, set: { event.round = $0.isEmpty ? nil : $0 }))
                }
                Picker("时间含义", selection: $event.isDeadline) { Text("开始时间").tag(false); Text("截止时间").tag(true) }.pickerStyle(.segmented)
                DatePicker("日期与时间", selection: $event.date, displayedComponents: [.date, .hourAndMinute])
                Text("所有时间按北京时间（UTC+8）保存与显示").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("提前提醒", selection: $event.reminderMinutes) {
                    Text("不提醒").tag(0); Text("5 分钟").tag(5); Text("15 分钟").tag(15); Text("30 分钟").tag(30); Text("1 小时").tag(60); Text("1 天").tag(1440)
                }
                TextField("地点 / 会议号", text: $event.location)
                TextField("会议 / 测评链接", text: $event.link)
                Picker("状态", selection: $event.status) { ForEach(EventStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }.textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("备注").font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $event.notes).font(.system(size: 12)).scrollContentBackground(.hidden).padding(7).frame(height: 75).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            if event.date < Date() && event.status == .pending { Text("这个时间已过去，保存后会出现在“待确认”中。").font(.system(size: 11)).foregroundStyle(.orange) }
            Spacer(minLength: 0)
            HStack {
                Text("保存即生效 · 通知需在设置中开启").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("保存安排") { do { save(try event.validated()) } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(accent)
            }
        }.padding(24).frame(width: 490, height: 600)
            .alert("请检查填写内容", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
}
