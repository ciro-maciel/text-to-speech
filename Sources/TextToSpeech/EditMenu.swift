// A menu bar app has no visible main menu, and AppKit delivers ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z to a text
// field only through the Edit menu's key equivalents. Without this, the key and token fields in
// Voice took typing but no paste. The menu is never shown (the app is an accessory); its items
// go to the first responder.
import AppKit

enum EditMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("edit.menu"))
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("edit.undo", Selector(("undo:")), "z", .command),
            ("edit.redo", Selector(("redo:")), "z", [.command, .shift]),
            ("edit.cut", #selector(NSText.cut(_:)), "x", .command),
            ("edit.copy", #selector(NSText.copy(_:)), "c", .command),
            ("edit.paste", #selector(NSText.paste(_:)), "v", .command),
            ("edit.selectAll", #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (key, action, equivalent, modifiers) in items {
            let item = NSMenuItem(title: L(key), action: action, keyEquivalent: equivalent)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
