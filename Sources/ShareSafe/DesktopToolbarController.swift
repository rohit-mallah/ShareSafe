import AppKit
import Combine

/// Small, session-only controls. Showing the toolbar neither starts capture nor
/// activates the app under the pointer; the user's app keeps its keyboard focus.
@MainActor
final class DesktopToolbarController {
    let panel: NSPanel
    let primaryButton = ToolbarButton(title: "Blur area")
    let editButton = ToolbarButton(title: "Move/remove")
    let modeButton = ToolbarButton(title: "")
    private let notice = NSTextField(wrappingLabelWithString: "")
    let undoButton = ToolbarButton(title: "")
    let clearButton = ToolbarButton(title: "Clear")
    let hideButton = ToolbarButton(title: "")

    private let overlays: DesktopOverlayController
    private var subscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var hasPosition = false

    init(overlays: DesktopOverlayController) {
        self.overlays = overlays
        panel = ToolbarPanel(contentRect: CGRect(x: 0, y: 0, width: 470, height: 56),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "ShareSafe — controls"
        panel.setAccessibilityLabel("ShareSafe controls")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.sharingType = .readWrite

        let material = NSVisualEffectView(frame: CGRect(origin: .zero, size: panel.frame.size))
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.appearance = NSAppearance(named: .darkAqua)
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.masksToBounds = true
        panel.contentView = material

        let brand = NSTextField(labelWithString: "ShareSafe")
        brand.font = .systemFont(ofSize: 12, weight: .semibold)
        brand.setContentHuggingPriority(.required, for: .horizontal)
        brand.setContentCompressionResistancePriority(.required, for: .horizontal)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 1),
                                     separator.heightAnchor.constraint(equalToConstant: 22)])

        primaryButton.bezelStyle = .rounded
        primaryButton.isBordered = true
        primaryButton.bezelColor = .systemMint
        primaryButton.contentTintColor = .black
        primaryButton.onClick = { [weak self] in self?.primaryAction() }
        modeButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Blur mode")
        modeButton.setAccessibilityLabel("Choose Content or Fixed area")
        modeButton.toolTip = "Content follows scrolling in supported apps. Fixed area stays in place."
        modeButton.onClick = { [weak self] in self?.showModeMenu() }
        editButton.onClick = { [weak self] in
            guard let self else { return }
            if self.overlays.isEditing { self.overlays.removeSelected() }
            else { self.overlays.toggleEditing() }
            self.refresh()
        }
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo last area")
        undoButton.setAccessibilityLabel("Undo last area")
        undoButton.toolTip = "Undo last area · ⌃⌥⌘Z"
        undoButton.onClick = { [weak self] in self?.overlays.undo(); self?.refresh() }
        clearButton.toolTip = "Clear all areas · ⌃⌥⌘C"
        clearButton.onClick = { [weak self] in self?.overlays.removeAll(); self?.refresh() }
        hideButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide toolbar")
        hideButton.setAccessibilityLabel("Hide toolbar")
        hideButton.toolTip = "Hide controls. Your blur areas stay in place."
        hideButton.onClick = { [weak self] in self?.hide() }

        let dragHandle = ToolbarDragHandle(frame: .zero)
        let stack = NSStackView(views: [dragHandle, brand, separator, primaryButton, modeButton,
                                       editButton, undoButton, clearButton, hideButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: material.topAnchor, constant: 12),
            stack.heightAnchor.constraint(equalToConstant: 32),
            dragHandle.widthAnchor.constraint(equalToConstant: 14),
            dragHandle.heightAnchor.constraint(equalToConstant: 30),
            primaryButton.widthAnchor.constraint(equalToConstant: 94),
            modeButton.widthAnchor.constraint(equalToConstant: 18),
            editButton.widthAnchor.constraint(equalToConstant: 98),
            undoButton.widthAnchor.constraint(equalToConstant: 28),
            clearButton.widthAnchor.constraint(equalToConstant: 48),
            hideButton.widthAnchor.constraint(equalToConstant: 24)
        ])

        notice.font = .systemFont(ofSize: 11)
        notice.textColor = .systemOrange
        notice.isHidden = true
        notice.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(notice)
        NSLayoutConstraint.activate([
            notice.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 12),
            notice.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -12),
            notice.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 4),
            notice.heightAnchor.constraint(equalToConstant: 30)
        ])

        subscription = overlays.objectWillChange.sink { [weak self] in
            // ObservableObject emits before the value changes.
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.positionOnPointerDisplay()
            }
        }
        refresh()
    }

    func show() {
        positionOnPointerDisplay()
        refresh()
        panel.orderFrontRegardless()
    }

    func hide() {
        overlays.finishInteraction()
        panel.orderOut(nil)
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel.close()
    }

    func refresh() {
        let interacting = overlays.isSelecting || overlays.isEditing
        let title = overlays.emergencyCovered ? "Restore" : interacting ? "Done" : overlays.followsContent ? "Blur content" : "Blur area"
        if primaryButton.title != title { primaryButton.title = title }
        primaryButton.toolTip = overlays.emergencyCovered ? "Restore your displays · ⌃⌥⌘B" :
            interacting ? "Finish selecting or editing · Escape" : overlays.followsContent ?
                "Drag inside text or a control to follow it · ⌃⌥⌘H" : "Drag a fixed area to blur · ⌃⌥⌘H"
        let editTitle = overlays.isEditing ? "Remove" : "Move/remove"
        if editButton.title != editTitle { editButton.title = editTitle }
        editButton.toolTip = overlays.isEditing ? "Remove selected area · Delete. Arrows move; Tab selects." :
            "Select, move or remove an area · ⌃⌥⌘E"
        editButton.isEnabled = !overlays.emergencyCovered && !overlays.isSelecting && overlays.editableRegionCount > 0
        undoButton.isEnabled = !overlays.emergencyCovered && overlays.regionCount > 0
        clearButton.isEnabled = !overlays.emergencyCovered && overlays.regionCount > 0
        modeButton.isEnabled = !overlays.emergencyCovered && !interacting
        let message = overlays.pausedContentCount > 0 ? overlays.status : overlays.lastError
        notice.stringValue = message ?? ""
        notice.isHidden = message == nil
        let height: CGFloat = message == nil ? 56 : 92
        if panel.frame.height != height { panel.setContentSize(CGSize(width: 470, height: height)) }
        panel.contentView?.toolTip = message ?? overlays.status
    }

    private func showModeMenu() {
        let menu = NSMenu(title: "Blur mode")
        for (title, content) in [("Content — follows scrolling", true), ("Fixed area — stays in place", false)] {
            let item = NSMenuItem(title: title, action: #selector(chooseMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = content
            item.state = overlays.followsContent == content ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: modeButton.bounds.minY), in: modeButton)
    }

    @objc private func chooseMode(_ item: NSMenuItem) {
        guard let content = item.representedObject as? Bool else { return }
        overlays.setContentFollowing(content)
        refresh()
    }

    private func primaryAction() {
        if overlays.emergencyCovered { overlays.toggleEmergencyCover() }
        else if overlays.isSelecting || overlays.isEditing { overlays.finishInteraction() }
        else { overlays.beginSelection() }
        refresh()
    }

    private func positionOnPointerDisplay() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        if !hasPosition || !visible.contains(panel.frame) {
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 20))
            hasPosition = true
        }
    }
}

@MainActor
private final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ToolbarButton: NSButton {
    var onClick: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        font = .systemFont(ofSize: 12, weight: .medium)
        bezelStyle = .recessed
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(invoke)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func invoke() { onClick?() }
}

@MainActor
private final class ToolbarDragHandle: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to move the toolbar"
        setAccessibilityElement(true)
        setAccessibilityLabel("Drag to move ShareSafe controls")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setFill()
        for x in [bounds.midX - 2, bounds.midX + 2] {
            for y in [bounds.midY - 4, bounds.midY, bounds.midY + 4] {
                NSBezierPath(ovalIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
            }
        }
    }
}
