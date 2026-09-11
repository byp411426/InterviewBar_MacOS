import AppKit
import SwiftUI
import UserNotifications
import Combine

@MainActor final class EventStore: ObservableObject {
    @Published private(set) var events: [InterviewEvent] = []
    @Published private(set) var results: [ApplicationResult] = []
    @Published private(set) var unscheduled: [UnscheduledEvent] = []
    @Published var error: String?
    @Published var now = Date()
    @Published var remindersEnabled = UserDefaults.standard.bool(forKey: "remindersEnabled")
    @Published var reminderMessage = "本机提醒尚未开启"
    private var writable = true
    private var scheduleTask: Task<Void, Never>?
    private let notificationsAllowed: Bool
    let repository: EventRepository
    init(directory: URL? = nil, notificationsAllowed: Bool = true) {
        self.notificationsAllowed = notificationsAllowed
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("InterviewBar")
        repository = EventRepository(url: directory.appendingPathComponent("events.json"))
        do {
            try ImportTransaction.recover(in: directory)
            if FileManager.default.fileExists(atPath: repository.url.path) { events = try repository.load() }
            else { events = []; try repository.save(events) }
        } catch { self.error = "读取日程失败，已保留原文件：\(error.localizedDescription)"; writable = false }
        loadResults()
        let pendingFile = directory.appendingPathComponent("unscheduled-events.json")
        if FileManager.default.fileExists(atPath: pendingFile.path) {
            do { unscheduled = try JSONDecoder().decode([UnscheduledEvent].self, from: Data(contentsOf: pendingFile)) }
            catch { self.error = "待通知安排读取失败：\(error.localizedDescription)"; writable = false }
        }
    }
    func loadResults() {
        let file = repository.url.deletingLastPathComponent().appendingPathComponent("application-results.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { results = try JSONDecoder().decode([ApplicationResult].self, from: Data(contentsOf: file)) }
        catch { self.error = "读取投递结果失败：\(error.localizedDescription)" }
    }
    func importMail(_ draft: MailDraft, capture: MailCapture, targetID: UUID?, expectedRow: [String]?) throws {
        guard writable else { throw DataError.invalid("数据读取失败，请先处理错误再导入。") }
        let directory = repository.url.deletingLastPathComponent()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let historyURL = directory.appendingPathComponent("import-history.json")
        var history = FileManager.default.fileExists(atPath: historyURL.path) ? try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: historyURL)) : [:]
        guard history[capture.digest] == nil else { throw DataError.invalid("这段邮件文字已经导入过，无需重复保存。") }
        var updated = events, updatedResults = results, updatedUnscheduled = unscheduled
        let existingIndex = targetID.flatMap { id in updated.firstIndex { $0.id == id } }
        if targetID != nil && existingIndex == nil { throw DataError.invalid("原日程已变化，请重新打开导入窗口。") }
        if let index = existingIndex, MailParser.companyKey(updated[index].company) != MailParser.companyKey(draft.company) { throw DataError.invalid("选择的日程与公司不一致，请重新选择。") }
        let note = "\(dateText(Date(), "yyyy-MM-dd")) 用户确认邮件导入。" + (capture.title.isEmpty ? "" : "\n" + capture.title)
        if draft.rejected {
            if let index = existingIndex { updated[index].status = .rejected; updated[index].notes += "\n" + note }
            updatedResults.append(ApplicationResult(id: UUID(), company: draft.company, role: draft.role, status: .rejected, updatedAt: Date(), notes: note))
        } else if draft.canSchedule {
            var event = try draft.event()
            if let index = existingIndex {
                let old = updated[index]
                event.id = old.id; event.createdAt = old.createdAt; event.reminderMinutes = old.reminderMinutes
                event.notes = old.notes + "\n" + note
                if event.kind == .interview && event.round == nil { event.round = old.round }
                if event.role.isEmpty { event.role = old.role }
                if event.link.isEmpty { event.link = old.link }
                if event.location.isEmpty { event.location = old.location }
                updated[index] = event
            } else { event.notes = note; updated.append(event) }
            let matches = updatedUnscheduled.indices.filter { MailParser.companyKey(updatedUnscheduled[$0].company) == MailParser.companyKey(draft.company) && updatedUnscheduled[$0].kind == draft.kind && updatedUnscheduled[$0].role == draft.role && updatedUnscheduled[$0].round == draft.round }
            if matches.count == 1 { updatedUnscheduled.remove(at: matches[0]) }
        } else {
            var pending = UnscheduledEvent(company: draft.company, role: draft.role, kind: draft.kindUncertain ? nil : draft.kind, round: draft.round, day: draft.day, time: draft.time, timing: draft.timing, timeNote: draft.timeNote, notes: note, location: draft.location, link: draft.link)
            let matches = updatedUnscheduled.indices.filter { !draft.company.isEmpty && MailParser.companyKey(updatedUnscheduled[$0].company) == MailParser.companyKey(draft.company) && updatedUnscheduled[$0].kind == pending.kind && updatedUnscheduled[$0].role == draft.role && updatedUnscheduled[$0].round == draft.round }
            if matches.count == 1 {
                let index = matches[0]; pending.id = updatedUnscheduled[index].id; pending.createdAt = updatedUnscheduled[index].createdAt; pending.notes = updatedUnscheduled[index].notes + "\n" + note
                updatedUnscheduled[index] = pending
            } else { updatedUnscheduled.append(pending) }
        }
        let sheetURL = directory.appendingPathComponent("application-sheet.json")
        var sheet = FileManager.default.fileExists(atPath: sheetURL.path) ? try JSONDecoder().decode(SheetSnapshot.self, from: Data(contentsOf: sheetURL)) : SheetSnapshot(title: "本机投递记录", importedAt: Date(), columns: ["序号", "公司", "岗位", "当前状态", "状态更新时间", "备注"], rows: [])
        guard sheet.version == 1, sheet.rows.allSatisfy({ $0.count == sheet.columns.count }), let companyColumn = sheet.columns.firstIndex(of: "公司") else { throw DataError.invalid("投递表缺少公司列或格式异常，请先检查。") }
        var rowIndex: Int?
        if let expectedRow {
            guard let index = sheet.rows.firstIndex(of: expectedRow), MailParser.companyKey(expectedRow[companyColumn]) == MailParser.companyKey(draft.company) else { throw DataError.invalid("投递记录已变化或公司不匹配，请重新识别。") }
            rowIndex = index
        }
        if rowIndex == nil { sheet.rows.append(Array(repeating: "", count: sheet.columns.count)); rowIndex = sheet.rows.count - 1 }
        let index = rowIndex!
        func set(_ column: String, _ value: String, preserveEmpty: Bool = false) {
            if preserveEmpty && value.isEmpty { return }
            if !sheet.columns.contains(column) { sheet.columns.append(column); for i in sheet.rows.indices { sheet.rows[i].append("") } }
            sheet.rows[index][sheet.columns.firstIndex(of: column)!] = value
        }
        if expectedRow == nil { set("序号", String(sheet.rows.count)) }
        set("公司", draft.company); set("岗位", draft.role, preserveEmpty: true)
        set("当前状态", draft.rejected ? "未通过" : (draft.kindUncertain ? "类型待确认" : draft.kind.rawValue) + (draft.round.isEmpty ? "" : " · " + draft.round) + (draft.canSchedule ? "-待进行" : "-时间或信息待通知"))
        set("状态更新时间", dateText(Date(), "yyyy-MM-dd"))
        let oldNote = sheet.columns.firstIndex(of: "备注").map { sheet.rows[index][$0] } ?? ""
        set("备注", oldNote + (oldNote.isEmpty ? "" : "\n") + note + (draft.rejected ? "" : "\n\(draft.day) \(draft.time) \(draft.canSchedule ? (draft.isDeadline ? "截止" : "开始") : draft.timing.label)\n\(draft.timeNote)"))
        if !sheet.title.contains("含邮件确认更新") { sheet.title += " · 含邮件确认更新" }
        history[capture.digest] = Date()
        let originals = directory.appendingPathComponent("mail-captures")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let original = originals.appendingPathComponent(capture.id.uuidString + ".json")
        try encoder.encode(capture).write(to: original, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path)
        do {
            try ImportTransaction.commit(["events.json": encoder.encode(EventFile(events: updated)), "application-results.json": encoder.encode(updatedResults), "application-sheet.json": encoder.encode(sheet), "import-history.json": encoder.encode(history), "unscheduled-events.json": encoder.encode(updatedUnscheduled)], in: directory)
        } catch {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("import-transaction.json").path) { writable = false }
            throw error
        }
        events = updated; results = updatedResults; unscheduled = updatedUnscheduled; schedule()
        NotificationCenter.default.post(name: .mailImportCommitted, object: nil)
    }
    var pending: [InterviewEvent] { events.filter { $0.status == .pending }.sorted { $0.date < $1.date } }
    var next: InterviewEvent? { pending.first { $0.date >= now } }
    @discardableResult func save(_ event: InterviewEvent) -> Bool {
        do {
            let clean = try event.validated()
            var updated = events
            if let index = updated.firstIndex(where: { $0.id == clean.id }) { updated[index] = clean } else { updated.append(clean) }
            return commit(updated)
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func commit(_ updated: [InterviewEvent]) -> Bool {
        guard writable else { error = "日程文件未成功读取，请先备份并检查原文件。"; return false }
        do { try repository.save(updated); events = updated; schedule(); return true }
        catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
    func setStatus(_ event: InterviewEvent, _ status: EventStatus) { var updated = event; updated.status = status; save(updated) }
    func enableReminders() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                remindersEnabled = granted
                UserDefaults.standard.set(granted, forKey: "remindersEnabled")
                if !granted { reminderMessage = "通知未获允许，可在系统设置 → 通知中开启" }
                schedule()
            } catch { self.error = "无法启用提醒：\(error.localizedDescription)" }
        }
    }
    func disableReminders() {
        remindersEnabled = false; UserDefaults.standard.set(false, forKey: "remindersEnabled"); schedule()
    }
    func schedule() {
        guard notificationsAllowed else { return }
        let previous = scheduleTask
        scheduleTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            guard remindersEnabled else { reminderMessage = "本机提醒尚未开启"; return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                reminderMessage = "系统通知未开启，请在系统设置 → 通知中允许"; return
            }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = shanghai
            let future = pending.filter { $0.reminderMinutes > 0 && $0.date.addingTimeInterval(-Double($0.reminderMinutes * 60)) > Date() }.sorted {
                $0.date.addingTimeInterval(-Double($0.reminderMinutes * 60)) < $1.date.addingTimeInterval(-Double($1.reminderMinutes * 60))
            }
            do {
                for event in future.prefix(60) {
                    let content = UNMutableNotificationContent()
                    content.title = "\(event.company) · \(event.kindLabel)\(event.isDeadline ? "即将截止" : "即将开始")"
                    content.body = "\(dateText(event.date))\n\(event.role)\(event.location.isEmpty ? "" : " · " + event.location)"
                    content.sound = .default
                    let fireDate = event.date.addingTimeInterval(-Double(event.reminderMinutes * 60))
                    let components = calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute], from: fireDate)
                    try await center.add(UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                }
                reminderMessage = "已排期 \(min(future.count, 60)) 项提醒 · 受系统通知设置影响"
            } catch { reminderMessage = "提醒排期失败：\(error.localizedDescription)" }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = EventStore()
    var item: NSStatusItem!
    let popover = NSPopover()
    let panelSize = PanelSize()
    var editor: NSWindow?
    var workspace: NSWindow?
    var journeyWindow: NSWindow?
    var widgetSettingsWindow: NSWindow?
    lazy var widgets = DesktopWidgets(store: store)
    var settingsWindow: NSWindow?
    var mailWindow: NSWindow?
    var modelWindow: NSWindow?
    let runtime = RuntimeSettings()
    private let statusName = "InterviewBar.Compact"
    private var recoveryTask: Task<Void, Never>?
    private var lastRecovery = "launch"
    var timer: Timer?
    var subscription: AnyCancellable?
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(receiveURL(_:reply:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        createStatusItem(resetPosition: !UserDefaults.standard.bool(forKey: "compactPositionInitialized"))
        UserDefaults.standard.set(true, forKey: "compactPositionInitialized")
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = panelSize.size
        panelSize.resized = { [weak self] size in self?.popover.contentSize = size; self?.writeRuntimeStatus() }
        popover.contentViewController = NSHostingController(rootView: Dashboard(store: store, sizing: panelSize, edit: { [weak self] in self?.showEditor($0) }, export: { [weak self] in self?.exportData() }, openWorkspace: { [weak self] in self?.showWorkspace() }, openSettings: { [weak self] in self?.showSettings() }, openJourney: { [weak self] in self?.showJourney() }, importMail: { [weak self] in self?.showMailImport(MailCapture(text: NSPasteboard.general.string(forType: .string) ?? "")) }).environment(\.locale, Locale(identifier: "zh_CN")).environment(\.timeZone, shanghai))
        subscription = store.$events.sink { [weak self] _ in DispatchQueue.main.async { self?.updateTitle(); self?.widgets.publishSnapshot() } }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.now = Date(); self?.updateTitle() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(wake(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        runtime.refresh()
        if CommandLine.arguments.contains("--enable-login-item") { runtime.setLoginEnabled(true) }
        widgets.openJourney = { [weak self] in self?.showJourney() }
        widgets.openEvent = { [weak self] in self?.showEditor($0) }
        widgets.restore(); widgets.publishSnapshot()
        updateTitle(); store.schedule()
        // Login launches stay quiet. Opening the installed app again invokes reopen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.verifyPlacement() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.writeRuntimeStatus() }
    }
    func createStatusItem(resetPosition: Bool) {
        let positionKey = "NSStatusItem Preferred Position \(statusName)"
        let savedPosition = UserDefaults.standard.object(forKey: positionKey)
        if let previous = item { NSStatusBar.system.removeStatusItem(previous) }
        item = nil
        item = NSStatusBar.system.statusItem(withLength: 28)
        if resetPosition {
            // AppKit has no public setter for ordering. Seed its autosave preference
            // only on first setup / explicit repair, then preserve user placement.
            // This preference is best-effort and must be checked after layout.
            UserDefaults.standard.set(260.0, forKey: positionKey)
        } else if let savedPosition {
            UserDefaults.standard.set(savedPosition, forKey: positionKey)
        }
        item.autosaveName = statusName
        item.behavior = []
        if !item.isVisible { item.isVisible = true }
        item.button?.target = self; item.button?.action = #selector(toggle)
        let icon = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "面试日程")
        icon?.isTemplate = true
        item.button?.image = icon
        item.button?.imagePosition = .imageOnly
    }
    @objc func wake(_ notification: Notification) {
        lastRecovery = notification.name.rawValue
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            // Screen and menu-bar layout may settle after the wake notification.
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self else { return }
            store.now = Date()
            if item.button == nil { createStatusItem(resetPosition: false) }
            if !item.isVisible { item.isVisible = true }
            updateTitle(); store.schedule(); runtime.refresh()
            verifyPlacement()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            writeRuntimeStatus()
        }
    }
    func verifyPlacement() {
        guard let window = item.button?.window else { return }
        let frame = window.frame
        // A notch has a top safe area and two auxiliary menu-bar areas.
        // Repair only an actual collision / off-screen item, not a user position.
        let screens = NSScreen.screens.map { MenuScreenGeometry(frame: $0.frame,
            left: $0.safeAreaInsets.top > 0 ? $0.auxiliaryTopLeftArea : nil,
            right: $0.safeAreaInsets.top > 0 ? $0.auxiliaryTopRightArea : nil) }
        let collision = MenuBarPlacement.needsRepair(frame, screens: screens)
        if collision { createStatusItem(resetPosition: true); updateTitle() }
    }
    func writeRuntimeStatus() {
        let frame = item.button?.window?.frame ?? .zero
        let screens = NSScreen.screens.map { ["frame": NSStringFromRect($0.frame), "rightMenuArea": NSStringFromRect($0.auxiliaryTopRightArea ?? .zero)] }
        let data: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "updatedAt": ISO8601DateFormatter().string(from: Date()), "lastRecovery": lastRecovery, "menuFrame": NSStringFromRect(frame), "visible": item.isVisible, "loginEnabled": runtime.loginEnabled, "loginMessage": runtime.loginMessage, "screens": screens, "panelSize": NSStringFromSize(panelSize.size), "panelFrame": NSStringFromRect(popover.contentViewController?.view.window?.frame ?? .zero)]
        let url = store.repository.url.deletingLastPathComponent().appendingPathComponent("runtime-status.json")
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { try? encoded.write(to: url, options: .atomic) }
    }
    func updateTitle() {
        if let event = store.next {
            item.button?.toolTip = "下一项：\(event.company) · \(event.kindLabel) · \(dateText(event.date))"
        } else { item.button?.toolTip = "面试日程 · 点击添加安排" }
        item.button?.title = ""
        item.length = 28
        item.button?.setAccessibilityLabel("面试日程")
    }
    @objc func toggle() { if popover.isShown { popover.performClose(nil) } else { show() } }
    func show() {
        guard let button = item.button else { return }
        store.now = Date(); NSApp.activate(ignoringOtherApps: true)
        if let screen = button.window?.screen {
            let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? screen.visibleFrame
            panelSize.maximum = NSSize(width: min(900, screen.visibleFrame.width - 32), height: max(1, anchor.minY - screen.visibleFrame.minY - 30))
            panelSize.set(panelSize.size)
        }
        popover.contentSize = panelSize.size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        writeRuntimeStatus()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    @objc func receiveURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URLComponents(string: string), url.scheme == "interviewbar" else { return }
        if url.host == "journey" { showJourney(); return }
        if url.host == "next" { showEditor(store.next); return }
        guard url.host == "import",
              let id = url.queryItems?.first(where: { $0.name == "id" })?.value.flatMap(UUID.init(uuidString:)) else { return }
        let file = store.repository.url.deletingLastPathComponent().appendingPathComponent("mail-inbox/\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 300_000 else { throw DataError.invalid("邮件内容过长。") }
            let capture = try JSONDecoder().decode(MailCapture.self, from: data)
            guard capture.id == id, capture.text.utf8.count <= 60_000 else { throw DataError.invalid("邮件内容格式无效。") }
            showMailImport(capture)
        } catch { store.error = "读取邮件失败：\(error.localizedDescription)"; show() }
    }
    func showMailImport(_ capture: MailCapture) {
        popover.performClose(nil)
        if let mailWindow, mailWindow.isVisible {
            let alert = NSAlert(); alert.messageText = "当前还有一封邮件正在核对"; alert.informativeText = "关闭或保存当前邮件后，再重新发送下一封。"; alert.runModal()
            mailWindow.makeKeyAndOrderFront(nil); return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 670), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "邮件识别 · 面试日程"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MailImportView(store: store, capture: capture, close: { [weak window] in window?.close() }))
        mailWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidBecomeActive(_ notification: Notification) { runtime.refresh() }
    func showSettings() {
        popover.performClose(nil)
        runtime.refresh()
        if let settingsWindow { NSApp.activate(ignoringOtherApps: true); settingsWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "设置 · 面试日程"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store, runtime: runtime, resetPosition: { [weak self] in
            self?.createStatusItem(resetPosition: true); self?.updateTitle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.writeRuntimeStatus() }
        }, export: { [weak self] in self?.exportData() }, quit: { NSApp.terminate(nil) }, modelSettings: { [weak self] in self?.showModelSettings() }, widgetSettings: { [weak self] in self?.showWidgetSettings() }))
        settingsWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func showWidgetSettings() {
        if let widgetSettingsWindow { NSApp.activate(ignoringOtherApps: true); widgetSettingsWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "桌面小组件"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WidgetSettingsView(widgets: widgets))
        widgetSettingsWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func showJourney() {
        popover.performClose(nil)
        if let journeyWindow { NSApp.activate(ignoringOtherApps: true); journeyWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "我的秋招之旅"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 620)
        window.contentView = NSHostingView(rootView: JourneyView(store: store, edit: { [weak self] in self?.showEditor($0) }))
        journeyWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func showWorkspace() {
        popover.performClose(nil)
        if let workspace { NSApp.activate(ignoringOtherApps: true); workspace.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "投递总表 · 面试日程"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 950, height: 600)
        window.contentView = NSHostingView(rootView: WorkspaceView(store: store, edit: { [weak self] in self?.showEditor($0) }, export: { [weak self] in self?.exportData() }).environment(\.locale, Locale(identifier: "zh_CN")).environment(\.timeZone, shanghai))
        workspace = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func showModelSettings() {
        if let modelWindow { NSApp.activate(ignoringOtherApps: true); modelWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AI 服务与用量 · 面试日程"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ModelSettingsView())
        modelWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func showEditor(_ event: InterviewEvent?) {
        popover.performClose(nil)
        if let editor, editor.isVisible { editor.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = event == nil ? "添加安排" : "编辑安排"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EventEditor(event: event ?? InterviewEvent(company: "", date: Date().addingTimeInterval(3600)), save: { [weak self, weak window] value in
            if self?.store.save(value) == true { window?.close(); self?.show() }
            else { let alert = NSAlert(); alert.messageText = self?.store.error ?? "保存失败"; alert.runModal() }
        }, cancel: { [weak self, weak window] in window?.close(); self?.show() }).environment(\.locale, Locale(identifier: "zh_CN")).environment(\.timeZone, shanghai))
        editor = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func exportData() {
        popover.performClose(nil)
        let panel = NSSavePanel(); panel.nameFieldStringValue = "面试日程-\(dateText(Date(), "yyyyMMdd")).csv"
        if panel.runModal() == .OK, let url = panel.url {
            func csv(_ text: String) -> String {
                let safe = ["=", "+", "-", "@", "\t", "\r"].contains(String(text.first ?? " ")) ? "'" + text : text
                return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            var rows = store.events.sorted { $0.date < $1.date }.map { event in
                [event.company, event.role, event.kindLabel, dateText(event.date, "yyyy-MM-dd HH:mm"), "Asia/Shanghai", event.isDeadline ? "截止" : "开始", event.status.rawValue, event.location, event.link, event.notes].map(csv).joined(separator: ",")
            }
            rows += store.results.map { result in
                [result.company, result.role, "投递结果", "", "Asia/Shanghai", "未记录日程时间", result.status.rawValue, "", "", result.notes].map(csv).joined(separator: ",")
            }
            rows += store.unscheduled.map { item in
                let time = item.day + (item.time.isEmpty ? "" : " " + item.time)
                let cells: [String] = [item.company, item.role, item.kind?.rawValue ?? "", time, "Asia/Shanghai", item.timing.label, "待通知", item.location ?? "", item.link ?? "", item.timeNote + "\n" + item.notes]
                return cells.map(csv).joined(separator: ",")
            }
            let content = "\u{FEFF}公司,岗位,类型,时间,时区,时间含义,状态,地点或会议号,链接,备注\r\n" + rows.joined(separator: "\r\n")
            do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { store.error = error.localizedDescription }
        }
        show()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
}

#if !IMPORT_TEST
@main struct Main {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--configure-model-key") {
            do {
                guard let key = readLine(strippingNewline: true) else { throw DataError.invalid("未收到密钥。") }
                try ModelKeychain.save(key, configuration: .current); try ModelConfiguration.current.persist()
                UserDefaults.standard.set(true, forKey: "mailModelEnabled")
                UserDefaults.standard.set(true, forKey: "mailModelConfigured")
                print("Model credential saved in Keychain; AI recognition enabled.")
            } catch { print(error.localizedDescription); exit(1) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--model-probe"), CommandLine.arguments.count > index + 1 {
            let file = CommandLine.arguments[index + 1]
            Task {
                do {
                    let text = try String(contentsOfFile: file, encoding: .utf8)
                    let capture = MailCapture(text: text)
                    let start = Date()
                    let result = try await MailModel.recognize(capture, bypassCache: true, fast: !CommandLine.arguments.contains("--legacy-thinking"))
                    let seconds = Date().timeIntervalSince(start)
                    if CommandLine.arguments.contains("--cache-probe") {
                        let cachedStart = Date()
                        _ = try await MailModel.recognize(capture)
                        print("Cache seconds: \(Date().timeIntervalSince(cachedStart))")
                    }
                    let report: [String: Any] = ["seconds": seconds, "company": result.company, "role": result.role, "kind": result.kindUncertain ? "" : result.kind.rawValue, "date": result.day, "time": result.time, "timing": result.timing.rawValue, "isDeadline": result.isDeadline, "link": result.link, "rejected": result.rejected, "warnings": result.warnings]
                    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                    print(String(data: data, encoding: .utf8)!); exit(0)
                } catch { print(error.localizedDescription); exit(1) }
            }
            dispatchMain()
        }
        let application = NSApplication.shared
        let delegate = AppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
#endif
