import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

func validatedSheetURL(_ text: String) -> URL? {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", let host = url.host,
          host == "feishu.cn" || host.hasSuffix(".feishu.cn") || host == "larksuite.com" || host.hasSuffix(".larksuite.com"),
          url.user == nil, url.password == nil else { return nil }
    return url
}

@MainActor final class SheetStore: ObservableObject {
    @Published var snapshot: SheetSnapshot?
    @Published var error: String?
    let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("InterviewBar/application-sheet.json")
    init() { reload() }
    func reload() {
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let value = try JSONDecoder().decode(SheetSnapshot.self, from: Data(contentsOf: file))
                guard value.version == 1, value.rows.allSatisfy({ $0.count == value.columns.count }) else { throw DataError.invalid("投递表数据格式不支持。原文件已保留。") }
                snapshot = value
            } catch { self.error = error.localizedDescription }
        }
    }
    func importFile() {
        guard !FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("import-transaction.json").path) else { error = "上次邮件导入未完成，请重新打开应用恢复后再导入表格。"; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText]; panel.allowsMultipleSelection = false
        panel.message = "选择从飞书导出的 CSV / TSV；第一行应为列名。只更新本地副本，不修改飞书。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 20_000_000 else { throw DataError.invalid("文件超过 20 MB，请分表导出。") }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw DataError.invalid("请导出 UTF-8 CSV 或 TSV。") }
            let value = try SheetSnapshot.parse(text, title: url.deletingPathExtension().lastPathComponent)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { try Data(contentsOf: file).write(to: file.appendingPathExtension("backup"), options: .atomic) }
            try encoder.encode(value).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            snapshot = value
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor final class SheetWeb: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let view: WKWebView
    @Published var message = "点击“加载原表”，使用飞书账号查看完整投递记录。"
    @Published var loading = false
    @Published var started = false
    override init() {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .default()
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init(); view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
    }
    func load(_ text: String) {
        guard let url = validatedSheetURL(text) else { message = "请填写自己的 HTTPS 飞书表格链接。"; return }
        UserDefaults.standard.set(url.absoluteString, forKey: "applicationSheetURL")
        started = true; view.load(URLRequest(url: url))
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; message = "正在加载飞书页面…" }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        message = webView.url?.host?.contains("accounts.") == true ? "请登录有原表访问权限的飞书账号。此窗口的登录状态与 Chrome 独立。" : "当前显示飞书在线页面；权限与内容以飞书为准。"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func failed(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { loading = false; message = "加载失败：\(error.localizedDescription)。可在浏览器打开原表。" } }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["https", "http", "about"].contains(url.scheme ?? "") { decisionHandler(.allow) }
        else { decisionHandler(.cancel); message = "网页请求打开外部应用，请使用上方“浏览器打开”继续。" }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
}
struct EmbeddedSheet: NSViewRepresentable {
    let web: SheetWeb
    func makeNSView(context: Context) -> WKWebView { web.view }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

struct GridRow: Identifiable { let id: String; let cells: [String] }
struct DetailGrid: NSViewRepresentable {
    var columns: [String]
    var rows: [GridRow]
    @Binding var selection: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView(); table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 34; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsMultipleSelection = false; table.allowsColumnReordering = true
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false; scroll.scrollerStyle = .legacy
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let table = scroll.documentView as! NSTableView
        let coordinator = context.coordinator
        coordinator.parent = self
        let changedColumns = coordinator.columns != columns
        if changedColumns {
            for column in table.tableColumns { table.removeTableColumn(column) }
            for (index, name) in columns.enumerated() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index))); column.title = name
                column.width = name == "序号" ? 65 : (name.contains("备注") ? 330 : (name.contains("岗位") || name.contains("链接") || name.contains("日期与时间") ? 230 : 155))
                column.minWidth = 75; column.maxWidth = 600
                column.sortDescriptorPrototype = NSSortDescriptor(key: String(index), ascending: true)
                table.addTableColumn(column)
            }
            coordinator.columns = columns
        }
        coordinator.sorted = rows
        coordinator.sort(table.sortDescriptors)
        table.reloadData()
        if changedColumns {
            table.setFrameSize(NSSize(width: table.tableColumns.reduce(0) { $0 + $1.width }, height: max(scroll.contentSize.height, CGFloat(rows.count) * 34)))
            DispatchQueue.main.async {
                scroll.layoutSubtreeIfNeeded()
                if !rows.isEmpty { table.scrollRowToVisible(0) }
                if !columns.isEmpty { table.scrollColumnToVisible(0) }
            }
        }
        if let selection, let index = coordinator.sorted.firstIndex(where: { $0.id == selection }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: DetailGrid; var sorted: [GridRow] = []; var columns: [String] = []
        init(_ parent: DetailGrid) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { sorted.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let raw = tableColumn?.identifier.rawValue, let index = Int(raw), row < sorted.count, index < sorted[row].cells.count else { return nil }
            let label = NSTextField(labelWithString: sorted[row].cells[index]); label.lineBreakMode = .byTruncatingTail; label.font = .systemFont(ofSize: 12); label.toolTip = label.stringValue
            return label
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table = notification.object as? NSTableView else { return }
            let index = table.selectedRow; let value = index >= 0 && index < sorted.count ? sorted[index].id : nil
            if parent.selection != value { DispatchQueue.main.async { self.parent.selection = value } }
        }
        func sort(_ descriptors: [NSSortDescriptor]) {
            guard let descriptor = descriptors.first, let key = descriptor.key, let index = Int(key) else { return }
            sorted.sort { a, b in
                let result = a.cells[index].localizedStandardCompare(b.cells[index])
                return descriptor.ascending ? result == .orderedAscending : result == .orderedDescending
            }
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { sort(tableView.sortDescriptors); tableView.reloadData() }
    }
}

struct WorkspaceView: View {
    @ObservedObject var store: EventStore
    @StateObject private var sheet = SheetStore()
    @StateObject private var web = SheetWeb()
    let edit: (InterviewEvent?) -> Void
    let export: () -> Void
    var editUnscheduled: (UnscheduledEvent) -> Void = { _ in }
    @State private var sheetAddress = UserDefaults.standard.string(forKey: "applicationSheetURL") ?? ""
    @State private var page = "本地投递表"
    @State private var search = ""
    @State private var selection: String?
    @State private var pendingDeletion: UnscheduledEvent?
    @State private var status = "全部"
    @State private var kindFilter = EventKindFilter.all
    private let eventColumns = ["公司", "岗位", "类型", "日期与时间（北京时间）", "开始 / 截止", "状态", "地点 / 会议号", "会议 / 测评链接", "提前提醒", "备注"]
    var columns: [String] { page == "日程明细" ? eventColumns : sheet.snapshot?.columns ?? [] }
    var rows: [GridRow] {
        var data: [GridRow]
        if page == "日程明细" {
            data = store.events.sorted { $0.date < $1.date }.filter { kindFilter.matches($0.kind) && (status == "全部" || $0.status.rawValue == status) }.map { event in
                GridRow(id: event.id.uuidString, cells: [event.company, event.role, event.kindLabel, dateText(event.date, "yyyy-MM-dd E HH:mm"), event.isDeadline ? "截止" : "开始", event.overdue(at: store.now) ? "时间已过 · 待确认" : event.status.rawValue, event.location, event.link, event.reminderMinutes == 0 ? "不提醒" : "提前 \(event.reminderMinutes) 分钟", event.notes])
            }
            data += store.results.filter { kindFilter == .all && (status == "全部" || $0.status.rawValue == status) }.map { result in
                GridRow(id: "result-" + result.id.uuidString, cells: [result.company, result.role, "投递结果", "未记录日程时间", "不适用", result.status.rawValue, "", "", "不提醒", result.notes + "\n结果记录于 " + dateText(result.updatedAt)])
            }
            do {
                data += store.unscheduled.filter { kindFilter.matches($0.kind) && (status == "全部" || $0.recordStatus.rawValue == status) }.map { item in
                    GridRow(id: "unscheduled-" + item.id.uuidString, cells: [item.displayCompany, item.role, (item.kind?.rawValue ?? "类型待确认") + (item.round.isEmpty ? "" : " · " + item.round), item.displayTime, item.timing.label, item.statusLabel, item.location ?? "", item.link ?? "", "不设置定时提醒", item.timeNote + "\n" + item.notes])
                }
            }
        } else { data = (sheet.snapshot?.rows ?? []).enumerated().map { GridRow(id: String($0.offset), cells: $0.element) } }
        return data.filter { search.isEmpty || $0.cells.contains(where: { $0.localizedCaseInsensitiveContains(search) }) }
    }
    var selectedRow: GridRow? { rows.first { $0.id == selection } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("投递与日程").font(.system(size: 25, weight: .semibold))
                    Text("公司进度放在总表，重要时间收进日程。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("页面", selection: $page) { Text("飞书原表").tag("飞书原表"); Text("本地投递表").tag("本地投递表"); Text("日程明细").tag("日程明细") }.pickerStyle(.segmented).frame(width: 320)
            }.padding(22)
            Divider()
            if page == "飞书原表" {
                TextField("粘贴你自己的飞书表格 HTTPS 链接，点击加载后保存", text: $sheetAddress).textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.top, 12)
                HStack {
                    Label("秋招进度实时监控表", systemImage: "tablecells").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button(web.started ? "重新加载原表" : "加载原表") { web.load(sheetAddress) }
                    Button("浏览器打开") { if let url = validatedSheetURL(sheetAddress) { NSWorkspace.shared.open(url) } }
                }.padding(14)
                Text(web.message).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 10)
                if web.loading { ProgressView().controlSize(.small).padding(4) }
                Divider()
                if web.started { EmbeddedSheet(web: web) }
                else {
                    VStack(spacing: 16) {
                        Image(systemName: "tablecells").font(.system(size: 42)).foregroundStyle(accent)
                        Text("你的完整投递表，放在这里看").font(.system(size: 21, weight: .medium))
                        Text("直接显示原飞书表，保留工作表、列和原有格式。\n首次使用需要登录有访问权限的飞书账号。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("加载飞书投递表") { web.load(sheetAddress) }.buttonStyle(.borderedProminent).tint(accent)
                        Text("在线操作会作用于飞书原表；不会自动同步到本地日程。").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索任意字段：公司、岗位、备注…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 330)
                    Text("\(rows.count) 条记录").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if page == "日程明细" {
                        Picker("类型", selection: $kindFilter) { ForEach(EventKindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 150)
                        Picker("状态", selection: $status) { Text("全部").tag("全部"); ForEach(EventStatus.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.frame(width: 140)
                        Button("导出 CSV", action: export)
                        Button("添加安排") { edit(nil) }.buttonStyle(.borderedProminent).tint(accent)
                    } else { Button("导入 CSV / TSV") { sheet.importFile() } }
                }.padding(14)
                if page == "本地投递表" {
                    Text(sheet.snapshot.map { "本地副本 · \($0.title) · 导入于 \(dateText($0.importedAt)) · 不自动与飞书同步" } ?? "尚未导入原表内容。可从飞书导出 CSV / TSV 后导入，原列名和所有字段都会保留。").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
                }
                Divider()
                HSplitView {
                    if columns.isEmpty {
                        VStack(spacing: 12) { Image(systemName: "square.and.arrow.down").font(.system(size: 32)); Text("导入后，可离线搜索和查看详细投递表"); Button("选择表格文件") { sheet.importFile() } }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { DetailGrid(columns: columns, rows: rows, selection: $selection).frame(minWidth: 550) }
                    VStack(alignment: .leading, spacing: 12) {
                        if let row = selectedRow {
                            Text(row.cells[columns.firstIndex(of: "公司") ?? 0]).font(.system(size: 20, weight: .semibold)).textSelection(.enabled)
                            if page == "日程明细", let event = store.events.first(where: { $0.id.uuidString == row.id }) { Button("编辑这项安排") { edit(event) } }
                            if page == "日程明细", let pending = store.unscheduled.first(where: { "unscheduled-" + $0.id.uuidString == row.id }) {
                                Button("编辑安排") { editUnscheduled(pending) }
                                Menu("更多操作") { UnscheduledMenuActions(item: pending, store: store, edit: { editUnscheduled(pending) }, delete: { pendingDeletion = pending }) }
                            }
                            ScrollView {
                                VStack(alignment: .leading, spacing: 15) {
                                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(column).font(.system(size: 11)).foregroundStyle(.secondary)
                                            Text(row.cells[index].isEmpty ? "未填写" : row.cells[index]).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                            if let url = URL(string: row.cells[index]), ["http", "https"].contains(url.scheme ?? ""), url.host != nil { Link("打开链接 ↗", destination: url).font(.system(size: 11)) }
                                        }
                                    }
                                }
                            }
                        } else { Text("记录详情").font(.system(size: 17, weight: .medium)); Text("选择一行，在这里查看全部内容。\n表头可排序，列宽可拖动调整。").font(.system(size: 12)).foregroundStyle(.secondary); Spacer() }
                    }.padding(18).frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
                }
            }
            Divider()
            HStack {
                Text(page == "飞书原表" ? "来源：飞书原表 · 需要联网" : "仅在本机查看 · 原记录保持完整").font(.system(size: 10))
                Spacer()
                Text("邮件识别：菜单栏 → 粘贴识别邮件").font(.system(size: 10))
            }.foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 10)
        }.frame(minWidth: 950, minHeight: 570).background(Color(nsColor: .windowBackgroundColor))
            .unscheduledDeletion(item: $pendingDeletion, store: store)
            .onChange(of: page) { _ in selection = nil; search = "" }
            .onReceive(NotificationCenter.default.publisher(for: .mailImportCommitted)) { _ in sheet.reload() }
            .alert("投递表提示", isPresented: Binding(get: { sheet.error != nil || store.error != nil }, set: { if !$0 { sheet.error = nil; store.error = nil } })) { Button("好") { sheet.error = nil; store.error = nil } } message: { Text(sheet.error ?? store.error ?? "") }
    }
}
