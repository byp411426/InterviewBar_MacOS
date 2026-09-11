import AppKit

@main struct ApplicationMenuTests {
    @MainActor static func main() throws {
        struct Failure: Error { let message: String }
        func check(_ condition: Bool, _ message: String = "Editing result mismatch") throws {
            if !condition { throw Failure(message: message) }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.mainMenu = ApplicationMenu.make()
        let clipboard = NSPasteboard.general
        let saved = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            clipboard.clearContents()
            clipboard.writeObjects(saved.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            })
        }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 20, y: 90, width: 380, height: 30))
        field.stringValue = "https://example.com/assessment"
        window.contentView!.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let editor = field.currentEditor() as! NSTextView
        editor.allowsUndo = true
        func key(_ value: String, shift: Bool = false) throws {
            let modifiers: NSEvent.ModifierFlags = shift ? [.command, .shift] : [.command]
            let item = app.mainMenu!.items[1].submenu!.items.first {
                $0.keyEquivalent == value && $0.keyEquivalentModifierMask == modifiers
            }!
            try check(item.target == nil, "Editing actions must follow the responder chain")
            // CLI tests have no active application session; exercise the selected native editor.
            try check(window.firstResponder!.tryToPerform(item.action!, with: item), "Editing action was not handled")
        }
        try key("a")
        try check(editor.selectedRange().length == editor.string.utf16.count)
        try key("c")
        try check(clipboard.string(forType: .string) == field.stringValue)
        try key("x")
        try check(editor.string.isEmpty)
        try key("v")
        try check(editor.string == "https://example.com/assessment")
        // Undo and redo operate on the field editor's native undo manager.
        editor.breakUndoCoalescing()
        editor.undoManager!.removeAllActions()
        try key("a"); try key("x")
        try key("z")
        try check(editor.string == "https://example.com/assessment")
        try key("z", shift: true)
        try check(editor.string.isEmpty)

        let notes = NSTextView(frame: NSRect(x: 20, y: 10, width: 380, height: 70))
        notes.string = "演示备注：第一行\n第二行"
        window.contentView!.addSubview(notes)
        window.makeFirstResponder(notes)
        try key("a"); try key("c"); try key("x")
        try check(notes.string.isEmpty)
        try key("v")
        try check(notes.string == "演示备注：第一行\n第二行")
        print("PASS: native link field select/copy/cut/paste/undo/redo and multiline text editing; clipboard restored")
    }
}
