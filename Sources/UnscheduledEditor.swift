import SwiftUI

extension UnscheduledEvent {
    func validated() throws -> UnscheduledEvent {
        var copy = self
        copy.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.day = day.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.time = time.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.link = (link ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let link = copy.link, !link.isEmpty {
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw DataError.invalid("请填写完整的 http:// 或 https:// 链接。")
            }
        }
        for (value, format, label) in [(copy.day, "yyyy-MM-dd", "日期"), (copy.time, "HH:mm", "时刻")] where !value.isEmpty {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = shanghai; formatter.dateFormat = format; formatter.isLenient = false
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
                throw DataError.invalid("\(label)格式应为 \(format)，不知道时可以留空。")
            }
        }
        if copy.kind != .interview { copy.round = "" }
        return copy
    }
    func scheduledEvent() throws -> InterviewEvent? {
        guard timing == .exact, !company.isEmpty, let kind, !day.isEmpty, !time.isEmpty else { return nil }
        var draft = MailDraft()
        draft.company = company; draft.role = role; draft.kind = kind; draft.round = round
        draft.day = day; draft.time = time; draft.location = location ?? ""; draft.link = link ?? ""
        draft.isDeadline = isDeadline ?? false
        var event = try draft.event()
        event.id = id; event.createdAt = createdAt; event.status = recordStatus
        event.notes = notes + (timeNote.isEmpty ? "" : "\n原时间说明：" + timeNote)
        return event
    }
}

struct UnscheduledEditor: View {
    @State var item: UnscheduledEvent
    let save: (UnscheduledEvent) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("修正安排").font(.system(size: 25, weight: .semibold))
            Text("识别有误可直接修改；不知道的时间留空，也可以标记已完成。").font(.system(size: 12)).foregroundStyle(.secondary)
            Form {
                TextField("公司（可留空）", text: $item.company)
                TextField("岗位", text: $item.role)
                Picker("类型", selection: $item.kind) {
                    Text("待确认").tag(nil as EventKind?)
                    ForEach(EventKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                if item.kind == .interview { TextField("面试轮次", text: $item.round) }
                Picker("状态", selection: Binding(get: { item.recordStatus }, set: { item.status = $0 })) {
                    ForEach(EventStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("时间信息", selection: $item.timing) {
                    ForEach(MailTiming.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("日期（yyyy-MM-dd，可留空）", text: $item.day)
                TextField("时刻（HH:mm，可留空）", text: $item.time)
                Picker("时间含义", selection: Binding(get: { item.isDeadline ?? false }, set: { item.isDeadline = $0 })) {
                    Text("开始时间").tag(false); Text("截止时间").tag(true)
                }.pickerStyle(.segmented)
                TextField("原时间说明", text: $item.timeNote)
                TextField("地点 / 会议号", text: Binding(get: { item.location ?? "" }, set: { item.location = $0 }))
                TextField("会议 / 测评链接", text: Binding(get: { item.link ?? "" }, set: { item.link = $0 }))
            }.textFieldStyle(.roundedBorder)
            Text("备注").foregroundStyle(.secondary)
            TextEditor(text: $item.notes).font(.system(size: 12)).frame(minHeight: 65)
                .padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            Text("补齐公司、类型和具体时间后会移入普通日程；未补齐时仍保留记录，不设置定时提醒。按周统计需要明确的安排时间。").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Spacer(); Button("取消", action: cancel).keyboardShortcut(.cancelAction); Button("保存安排") { save(item) }.keyboardShortcut(.defaultAction).tint(accent) }
        }.padding(24).frame(width: 600, height: 650)
    }
}
