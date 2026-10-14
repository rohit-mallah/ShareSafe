import AppKit
import Carbon
import Combine

@main
enum ShareSafeApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlays = DesktopOverlayController()
    private var statusItem: NSStatusItem?
    private var activeMenu: DesktopStatusMenu?
    private var subscription: AnyCancellable?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var shortcutWarning: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeStatusItem()
        registerShortcuts()
        subscription = overlays.objectWillChange.sink { [weak self] in
            // Published notifications precede the mutation; refresh next turn.
            DispatchQueue.main.async { [weak self] in self?.updateStatus() }
        }
        updateStatus()
        DispatchQueue.main.async { [weak self] in self?.overlays.beginSelection() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlays.beginSelection()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        subscription?.cancel()
        overlays.stop()
        for key in hotKeys { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("ShareSafe — click to blur; right-click for controls")
        }
        statusItem = item
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let symbol = overlays.emergencyCovered ? "shield.fill" :
            overlays.regionCount > 0 ? "rectangle.badge.checkmark" : "rectangle.dashed"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ShareSafe")
        image?.isTemplate = true
        button.image = image
        let state = overlays.lastError == nil ? overlays.status : "Review your hidden areas"
        button.toolTip = "ShareSafe — \(state)\nClick to blur an area. Right-click for undo, clear and quit."
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || overlays.emergencyCovered {
            showStatusMenu(sender)
        } else {
            overlays.beginSelection()
        }
    }

    private func showStatusMenu(_ button: NSStatusBarButton) {
        let controller = DesktopStatusMenu(regionCount: overlays.regionCount,
            isEditing: overlays.isEditing, emergencyCovered: overlays.emergencyCovered,
            error: overlays.lastError, shortcutWarning: shortcutWarning,
            visibleRegionCount: overlays.visibleRegionCount) { [weak self] action in
                // Close the tracking menu before installing new selection panels.
                DispatchQueue.main.async { [weak self] in self?.perform(action) }
            }
        activeMenu = controller
        controller.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        activeMenu = nil
    }

    private func perform(_ action: DesktopStatusAction) {
        switch action {
        case .selectArea: overlays.beginSelection()
        case .editAreas: overlays.toggleEditing()
        case .removeSelected: overlays.removeSelected()
        case .undo: overlays.undo()
        case .clear: overlays.removeAll()
        case .toggleEmergency: overlays.toggleEmergencyCover()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func registerShortcuts() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                id.signature == 0x53534645 else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let shortcut = DesktopShortcut.all.first(where: { $0.id == id.id }) {
                    delegate.perform(shortcut.action)
                }
            }
            return noErr
        }, 1, &type, context, &handler) == noErr else {
            shortcutWarning = "Shortcuts unavailable — use the menu-bar icon"
            return
        }
        for shortcut in DesktopShortcut.all {
            var reference: EventHotKeyRef?
            if RegisterEventHotKey(shortcut.keyCode, UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: 0x53534645, id: shortcut.id),
                GetApplicationEventTarget(), 0, &reference) == noErr, let reference {
                hotKeys.append(reference)
            } else {
                shortcutWarning = "A shortcut is in use — use the menu-bar icon"
            }
        }
    }
}
