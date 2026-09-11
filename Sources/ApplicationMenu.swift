import AppKit

/// Accessory apps also need an Edit menu to route keyboard shortcuts to the field editor.
@MainActor enum ApplicationMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        let application = NSMenuItem()
        application.submenu = NSMenu(title: "面试日程")
        application.submenu?.addItem(withTitle: "退出面试日程", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(application)

        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let actions = NSMenu(title: "编辑")
        func add(_ title: String, _ action: String, _ key: String, shift: Bool = false) {
            let item = actions.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            // A nil target preserves native selection, undo, and secure-field behavior.
            item.target = nil
        }
        add("撤销", "undo:", "z")
        add("重做", "redo:", "z", shift: true)
        actions.addItem(.separator())
        add("剪切", "cut:", "x")
        add("复制", "copy:", "c")
        add("粘贴", "paste:", "v")
        add("全选", "selectAll:", "a")
        edit.submenu = actions
        menu.addItem(edit)
        return menu
    }
}
