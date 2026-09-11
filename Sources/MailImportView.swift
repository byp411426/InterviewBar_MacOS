import AppKit
import SwiftUI

struct MailImportView: View {
    @ObservedObject var store: EventStore
    @State private var capture: MailCapture
    @State private var raw: String
    @State private var draft: MailDraft
    @State private var eventID = ""
    @State private var rowID = -1
    @State private var error: String?
    @State private var saved = false
    @State private var sheet: SheetSnapshot?
    @State private var useModel = UserDefaults.standard.bool(forKey: "mailModelEnabled")
    @State private var analyzing = false
    @State private var analysisReady = false
    @State private var requestID = UUID()
    @State private var activeText = ""
    @State private var requestTask: Task<Void, Never>?
    @State private var startedAt = Date()
    @State private var elapsed: Double?
    var close: () -> Void

    init(store: EventStore, capture: MailCapture, close: @escaping () -> Void) {
        self.store = store; self.close = close
        _capture = State(initialValue: capture); _raw = State(initialValue: capture.text)
        _draft = State(initialValue: MailParser.parse(capture.text, knownCompanies: store.events.map(\.company)))
    }
    var eventMatches: [InterviewEvent] { store.events.filter { MailParser.companyKey($0.company) == MailParser.companyKey(draft.company) } }
    var rowMatches: [Int] {
        guard !draft.company.isEmpty, let sheet, let column = sheet.columns.firstIndex(of: "公司") else { return [] }
        return sheet.rows.indices.filter { sheet.rows[$0].count == sheet.columns.count && MailParser.companyKey(sheet.rows[$0][column]) == MailParser.companyKey(draft.company) }
    }
    func pickMatches() {
        let possible = eventMatches.filter { !draft.company.isEmpty && draft.canSchedule && $0.kind == draft.kind && (draft.round.isEmpty || $0.round == nil || $0.round == draft.round) }
        eventID = possible.count == 1 ? possible[0].id.uuidString : ""
        rowID = rowMatches.count == 1 ? rowMatches[0] : -1
    }
    func readSheet() {
        let file = store.repository.url.deletingLastPathComponent().appendingPathComponent("application-sheet.json")
        if let data = try? Data(contentsOf: file) { sheet = try? JSONDecoder().decode(SheetSnapshot.self, from: data) }
        pickMatches()
    }
    func cancelRecognition() {
        requestTask?.cancel(); requestID = UUID(); analyzing = false; analysisReady = false
        error = "已取消识别，可以重新识别或切换本机规则。"
    }
    func recognize(force: Bool = false) {
        if analyzing && activeText == raw && !force { return }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, raw.utf8.count <= 60_000 else { error = "请粘贴邮件正文，最多约 2 万个汉字。"; return }
        requestTask?.cancel(); let token = UUID(); requestID = token
        saved = false; error = nil; analysisReady = false
        let input = raw
        activeText = input
        if !useModel {
            capture.text = input; draft = MailParser.parse(input, knownCompanies: store.events.map(\.company))
            analysisReady = true; analyzing = false; pickMatches(); return
        }
        analyzing = true; startedAt = Date(); elapsed = nil
        var candidate = capture; candidate.text = input
        requestTask = Task { @MainActor in
            do {
                var result = try await MailModel.recognize(candidate, bypassCache: force)
                guard !Task.isCancelled, requestID == token, raw == input else { return }
                if let known = store.events.map(\.company).first(where: { MailParser.companyKey($0) == MailParser.companyKey(result.company) }) { result.company = known }
                capture = candidate; draft = result; analysisReady = true; elapsed = Date().timeIntervalSince(startedAt); pickMatches()
            } catch {
                guard !Task.isCancelled, requestID == token else { return }
                self.error = "AI 识别失败：\(error.localizedDescription) 可重试或切换本机规则，当前结果未替换。"
            }
            if requestID == token { analyzing = false }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("从邮件添加安排").font(.system(size: 23, weight: .semibold))
                    Text(useModel ? "AI 提取字段 · 未知项留空 · 核对后才保存" : "本机规则识别 · 未知项可留空保存").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("邮件原文").font(.headline)
                    Picker("识别方式", selection: $useModel) { Text("AI 识别").tag(true); Text("本机规则").tag(false) }.pickerStyle(.segmented)
                    TextEditor(text: $raw).font(.system(size: 13)).padding(7).background(Color.primary.opacity(0.03)).frame(maxHeight: .infinity)
                    HStack {
                        Button("粘贴剪贴板") { raw = NSPasteboard.general.string(forType: .string) ?? ""; recognize() }
                        if analyzing { Button("停止识别") { cancelRecognition() } }
                        else { Button("重新识别") { recognize(force: true) } }
                    }
                    Text(useModel ? "使用 \(ModelConfiguration.current.model)。点击识别会将这段正文发给 \((try? ModelConfiguration.current.endpoint.host) ?? "配置的模型服务")；API 密钥保存在本机钥匙串。" : "仅使用本机规则，不向模型服务发送邮件。").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(width: 335)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("请核对识别结果").font(.headline)
                        TextField("公司（可留空）", text: $draft.company)
                        TextField("岗位（可留空）", text: $draft.role)
                        Picker("类型", selection: Binding<EventKind?>(get: { draft.kindUncertain ? nil : draft.kind }, set: { draft.kindUncertain = $0 == nil; if let kind = $0 { draft.kind = kind } })) {
                            Text("待确认（留空）").tag(nil as EventKind?)
                            ForEach(EventKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }
                        TextField("轮次，例如二面（可留空）", text: $draft.round)
                        Toggle("这是一封未通过通知", isOn: $draft.rejected)
                        if !draft.rejected {
                            Picker("时间信息", selection: $draft.timing) { ForEach(MailTiming.allCases, id: \.self) { Text($0.label).tag($0) } }
                            HStack { TextField("日期（可留空）", text: $draft.day); TextField("时刻（可留空）", text: $draft.time).frame(width: 125) }
                            Picker("时间含义", selection: $draft.isDeadline) { Text("开始时间").tag(false); Text("截止时间").tag(true) }.pickerStyle(.segmented)
                            Text(draft.canSchedule ? "北京时间 · 确认后安排提醒" : "未知项可以留空 · 保存为待通知，不设置定时提醒").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("原文时间说明（可留空）", text: $draft.timeNote, axis: .vertical).lineLimit(2...4)
                            TextField("会议号 / 地点", text: $draft.location)
                            TextField("面试 / 测评链接", text: $draft.link)
                        }
                        ForEach(draft.warnings, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                        Divider()
                        Picker("日程处理", selection: $eventID) {
                            Text(draft.rejected ? "仅保存投递结果，不创建日程" : draft.canSchedule ? "新增一项安排" : "保存待通知安排，不设置提醒").tag("")
                            ForEach(eventMatches) { event in Text("更新：\(event.company) \(event.kindLabel) \(dateText(event.date, "M/d HH:mm"))").tag(event.id.uuidString) }
                        }
                        if let old = eventMatches.first(where: { $0.id.uuidString == eventID }) {
                            Text("原安排：\(dateText(old.date)) · \(old.status.rawValue)\n确认后更新这条记录，保留原有备注和提醒设置。").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Picker("投递表处理", selection: $rowID) {
                            Text("新增投递记录").tag(-1)
                            ForEach(rowMatches, id: \.self) { index in
                                Text("更新：" + (sheet?.rows[index].prefix(3).joined(separator: " · ") ?? "")).tag(index)
                            }
                        }
                        Text("更新的是本地投递表，飞书云端不会自动修改。").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.textFieldStyle(.roundedBorder).padding(.trailing, 5).disabled(analyzing)
                }.frame(maxWidth: .infinity)
            }.frame(maxHeight: .infinity)
            if let error { Text(error).foregroundStyle(.red).font(.system(size: 12)) }
            if analyzing {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("AI 正在识别 · 已等待 \(Int(max(0, context.date.timeIntervalSince(startedAt)))) 秒").font(.system(size: 12))
                        if context.date.timeIntervalSince(startedAt) >= 12 { Text("服务响应较慢，可停止后重试").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                }
            } else if analysisReady && useModel, let elapsed {
                Text(elapsed < 0.1 ? "已复用刚才的识别结果 · 请核对后保存" : String(format: "AI 识别完成 · %.1f 秒 · 请核对后保存", elapsed)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if saved { Label("已保存，投递表和日程已一起更新", systemImage: "checkmark.circle.fill").foregroundStyle(accent) }
            HStack {
                Spacer()
                Button(saved ? "完成" : "取消", action: close).keyboardShortcut(.cancelAction)
                Button("确认保存到投递表与日程") {
                    do {
                        guard raw == capture.text else { throw DataError.invalid("原文已修改，请先点击“重新识别”。") }
                        guard !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DataError.invalid("请先粘贴邮件正文。") }
                        let row = rowID >= 0 ? sheet?.rows[rowID] : nil
                        try store.importMail(draft, capture: capture, targetID: UUID(uuidString: eventID), expectedRow: row)
                        saved = true; error = nil
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).tint(accent).disabled(saved || analyzing || (useModel && !analysisReady))
            }
        }.padding(24).frame(width: 860, height: 670)
            .onAppear { readSheet(); if !analysisReady && !analyzing && !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { recognize() } }
            .onChange(of: draft.company) { _ in pickMatches() }
            .onChange(of: useModel) { _ in recognize(force: true) }
            .onChange(of: raw) { _ in if raw != activeText { requestTask?.cancel(); requestID = UUID(); analyzing = false; analysisReady = false; saved = false } }
            .onDisappear { requestTask?.cancel(); requestID = UUID() }
    }
}
