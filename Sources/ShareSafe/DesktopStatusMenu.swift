import AppKit
import Carbon

enum DesktopStatusAction: String, Hashable {
    case selectArea, editAreas, removeSelected, undo, clear, toggleEmergency, quit
}

struct DesktopShortcut {
    let id: UInt32
    let action: DesktopStatusAction
    let keyCode: UInt32
    let label: String

    static let all: [DesktopShortcut] = [
        .init(id: 1, action: .selectArea, keyCode: UInt32(kVK_ANSI_H), label: "⌃⌥⌘H"),
        .init(id: 2, action: .toggleEmergency, keyCode: UInt32(kVK_ANSI_B), label: "⌃⌥⌘B"),
        .init(id: 3, action: .editAreas, keyCode: UInt32(kVK_ANSI_E), label: "⌃⌥⌘E"),
        .init(id: 4, action: .undo, keyCode: UInt32(kVK_ANSI_Z), label: "⌃⌥⌘Z"),
        .init(id: 5, action: .clear, keyCode: UInt32(kVK_ANSI_C), label: "⌃⌥⌘C")
    ]
}

/// Owns its action targets for the lifetime of the tracking menu. Building this
/// menu never starts capture or creates a desktop overlay.
@MainActor
final class DesktopStatusMenu: NSObject {
    let menu = NSMenu(title: "ShareSafe")
    private let performAction: (DesktopStatusAction) -> Void

    init(regionCount: Int, isEditing: Bool, emergencyCovered: Bool, error: String?,
         shortcutWarning: String?, performAction: @escaping (DesktopStatusAction) -> Void) {
        self.performAction = performAction
        super.init()
        menu.autoenablesItems = false
        info("ShareSafe")
        info(emergencyCovered ? "All displays hidden" : regionCount == 0 ? "Drag an area to blur" :
             "\(regionCount) \(regionCount == 1 ? "area" : "areas") hidden")
        menu.addItem(.separator())
        action(regionCount == 0 ? "Blur an area" : "Blur another area", .selectArea,
               enabled: !emergencyCovered)
        let canEdit = regionCount > 0 && !emergencyCovered
        action(isEditing ? "Finish editing" : "Move / remove areas", .editAreas, enabled: canEdit)
        if isEditing {
            action("Remove selected area", .removeSelected, enabled: canEdit, shortcut: "Delete")
            info("Arrows move · Shift moves faster · Tab selects")
        }
        action("Undo last area", .undo, enabled: canEdit)
        action("Clear all areas", .clear, enabled: canEdit)
        menu.addItem(.separator())
        action(emergencyCovered ? "Restore screen" : "Hide all displays", .toggleEmergency)
        if let error {
            menu.addItem(.separator())
            let warning = info("Review your areas after the screen change")
            warning.toolTip = error
        }
        if let shortcutWarning { info(shortcutWarning) }
        menu.addItem(.separator())
        info("Share your entire screen in your meeting")
        info("Blur is visible on your screen too")
        action("Quit ShareSafe", .quit)
    }

    @discardableResult
    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    private func action(_ title: String, _ action: DesktopStatusAction,
                        enabled: Bool = true, shortcut: String? = nil) {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        item.isEnabled = enabled
        if let label = shortcut ?? DesktopShortcut.all.first(where: { $0.action == action })?.label {
            item.title += "   \(label)"
        }
        menu.addItem(item)
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard sender.isEnabled, let raw = sender.representedObject as? String,
              let action = DesktopStatusAction(rawValue: raw) else { return }
        performAction(action)
    }
}
