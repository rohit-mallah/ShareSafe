import AppKit
import Combine
import ShareSafeCore

/// Session-only blur or solid windows. These protect captures that include desktop overlay windows;
/// they cannot alter another application's individually captured window or browser tab.
@MainActor
final class DesktopOverlayController: ObservableObject {
    @Published var maskStyle: MaskStyle = .blur
    @Published private(set) var regionCount = 0
    @Published private(set) var isSelecting = false
    @Published private(set) var isEditing = false
    @Published private(set) var emergencyCovered = false
    @Published private(set) var status = "Ready to hide an area"
    @Published private(set) var lastError: String?

    private struct Display: Equatable {
        let id: UInt32
        let frame: CGRect
        let scale: CGFloat

        init?(_ screen: NSScreen) {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            id = number.uint32Value
            frame = screen.frame
            scale = screen.backingScaleFactor
        }
    }

    private struct Cover {
        let id: UUID
        let displayID: UInt32
        var frame: CGRect
        let panel: OverlayPanel
    }

    private var covers: [Cover] = []
    private var selectedCoverID: UUID?
    private var selectionPanels: [OverlayPanel] = []
    private var emergencyPanels: [OverlayPanel] = []
    private var displays: [Display] = []
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private weak var priorKeyWindow: NSWindow?
    private var stopped = false
    private var needsDisplayReview = false

    private var editableCovers: [Cover] {
        covers.filter { cover in displays.contains { $0.id == cover.displayID } }
    }

    init() {
        displays = NSScreen.screens.compactMap(Display.init)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                for cover in self.covers {
                    (cover.panel.contentView as? DesktopCoverSurface)?.reduceTransparency = reduce
                }
            }
        }
    }

    func beginSelection() {
        guard !stopped else { return }
        guard !emergencyCovered else {
            status = "Emergency cover is on. Turn it off to select an area."
            return
        }
        endInteraction()
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            lastError = "No display is available."
            status = "Unable to select an area"
            return
        }
        priorKeyWindow = NSApp.keyWindow
        isSelecting = true
        status = "Drag an area to hide. Escape cancels."
        installKeyMonitor()
        for screen in screens {
            guard let display = Display(screen) else { continue }
            let panel = makePanel(frame: display.frame, level: selectionLevel, opaque: false)
            panel.title = "ShareSafe — select an area"
            panel.setAccessibilityLabel("ShareSafe area selection. Drag to hide an area; Escape cancels.")
            panel.acceptsKeyFocus = true
            let view = SelectionSurface(frame: CGRect(origin: .zero, size: display.frame.size))
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.group)
            view.setAccessibilityLabel("Drag to select a hidden area. Escape cancels selection.")
            view.screenFrame = display.frame
            view.onCommit = { [weak self] rectangle in
                guard let self, self.isSelecting else { return }
                // Install the cover before removing selection windows.
                if let rectangle { self.addCover(rectangle, display: display) }
                self.endInteraction()
                self.updateStatus()
            }
            view.onCancel = { [weak self] in self?.cancelInteraction() }
            panel.contentView = view
            selectionPanels.append(panel)
            panel.orderFrontRegardless()
        }
        guard !selectionPanels.isEmpty else {
            cancelInteraction()
            lastError = "Display information is unavailable."
            return
        }
        let mouse = NSEvent.mouseLocation
        let target = selectionPanels.first { NSPointInRect(mouse, $0.frame) } ?? selectionPanels[0]
        target.makeKeyAndOrderFront(nil)
    }

    func toggleEditing() {
        guard !stopped else { return }
        if isEditing {
            endInteraction()
            updateStatus()
            return
        }
        guard !emergencyCovered else {
            status = "Emergency cover is on. Turn it off to edit areas."
            return
        }
        endInteraction()
        guard let last = editableCovers.last else {
            status = covers.isEmpty ? "Hide an area before editing." :
                "Your areas are on disconnected displays. Reconnect them or clear all areas."
            return
        }
        priorKeyWindow = NSApp.keyWindow
        isEditing = true
        installKeyMonitor()
        for cover in editableCovers { setEditing(true, on: cover.panel) }
        focusCover(last.id)
        updateStatus()
    }

    func removeSelected() {
        guard isEditing, !emergencyCovered, let selectedCoverID else { return }
        removeCover(selectedCoverID)
    }

    private func focusCover(_ id: UUID) {
        guard isEditing, let cover = editableCovers.first(where: { $0.id == id }) else { return }
        selectedCoverID = id
        for item in covers {
            (item.panel.contentView as? DesktopCoverSurface)?.selected = item.id == id
        }
        cover.panel.makeKeyAndOrderFront(nil)
        cover.panel.makeFirstResponder(cover.panel.contentView)
    }

    private func cycleCover(reverse: Bool) {
        let available = editableCovers
        guard isEditing else { return }
        guard !available.isEmpty else { endInteraction(); updateStatus(); return }
        let current = available.firstIndex(where: { $0.id == selectedCoverID }) ?? 0
        let next = (current + (reverse ? -1 : 1) + available.count) % available.count
        focusCover(available[next].id)
    }

    private func nudgeCover(_ id: UUID, delta: CGVector) {
        guard isEditing, selectedCoverID == id, let cover = covers.first(where: { $0.id == id }) else { return }
        moveCover(id, startFrame: cover.frame, delta: delta)
    }

    func undo() {
        guard !stopped, !emergencyCovered else { return }
        endInteraction()
        // Undo removes the most recently created remaining ordinary cover.
        guard let cover = covers.popLast() else { return }
        cover.panel.close()
        regionCount = covers.count
        if covers.isEmpty { endInteraction() }
        updateStatus()
    }

    func removeAll() {
        guard !stopped, !emergencyCovered else { return }
        endInteraction()
        covers.forEach { $0.panel.close() }
        covers.removeAll()
        regionCount = 0
        needsDisplayReview = false
        lastError = nil
        updateStatus()
    }

    func toggleEmergencyCover() {
        guard !stopped else { return }
        if emergencyCovered {
            // Ordinary covers are already present beneath the blankets.
            emergencyPanels.forEach { $0.close() }
            emergencyPanels.removeAll()
            emergencyCovered = false
            if needsDisplayReview {
                lastError = "Displays changed. Review every hidden area before sharing; their positions may be stale."
            }
            updateStatus()
        } else {
            installEmergencyBlankets()
            emergencyCovered = true
            endInteraction()
            updateStatus()
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        endInteraction()
        covers.forEach { $0.panel.close() }
        emergencyPanels.forEach { $0.close() }
        covers.removeAll()
        emergencyPanels.removeAll()
        regionCount = 0
        emergencyCovered = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        status = "Protection stopped"
    }

    private var coverLevel: NSWindow.Level { NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1) }
    private var selectionLevel: NSWindow.Level { NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2) }
    private var emergencyLevel: NSWindow.Level { NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3) }

    private func makePanel(frame: CGRect, level: NSWindow.Level, opaque: Bool) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = opaque ? .black : .clear
        panel.isOpaque = opaque
        panel.alphaValue = 1
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = opaque
        panel.sharingType = .readWrite
        panel.onEscape = { [weak self] in self?.cancelInteraction() }
        return panel
    }

    private func addCover(_ rectangle: CGRect, display: Display) {
        guard let frame = OverlayGeometry.clipped(rectangle, to: display.frame) else { return }
        let id = UUID()
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let panel = makePanel(frame: frame, level: coverLevel, opaque: maskStyle == .solid || reduceTransparency)
        panel.ignoresMouseEvents = true
        panel.title = "ShareSafe — hidden area"
        panel.setAccessibilityLabel("ShareSafe protected area")
        let surface = DesktopCoverSurface(frame: CGRect(origin: .zero, size: frame.size),
                                          style: maskStyle, reduceTransparency: reduceTransparency)
        surface.setAccessibilityElement(true)
        surface.setAccessibilityRole(.group)
        surface.setAccessibilityLabel("Protected area. In edit mode, drag to move or right-click to remove.")
        surface.onMove = { [weak self] startFrame, delta in self?.moveCover(id, startFrame: startFrame, delta: delta) }
        surface.onSelect = { [weak self] in self?.focusCover(id) }
        surface.onSelectNext = { [weak self] reverse in self?.cycleCover(reverse: reverse) }
        surface.onNudge = { [weak self] delta in self?.nudgeCover(id, delta: delta) }
        surface.onRemove = { [weak self] in self?.removeCover(id) }
        surface.onCancel = { [weak self] in self?.cancelInteraction() }
        panel.contentView = surface
        covers.append(Cover(id: id, displayID: display.id, frame: frame, panel: panel))
        regionCount = covers.count
        panel.orderFrontRegardless()
        if !needsDisplayReview { lastError = nil }
    }

    private func moveCover(_ id: UUID, startFrame: CGRect, delta: CGVector) {
        guard isEditing, let index = covers.firstIndex(where: { $0.id == id }),
              let display = displays.first(where: { $0.id == covers[index].displayID }),
              let frame = OverlayGeometry.moved(startFrame, by: delta, in: display.frame) else { return }
        covers[index].frame = frame
        covers[index].panel.setFrame(frame, display: true)
    }

    private func removeCover(_ id: UUID) {
        guard isEditing, let index = covers.firstIndex(where: { $0.id == id }) else { return }
        covers.remove(at: index).panel.close()
        regionCount = covers.count
        if let last = editableCovers.last {
            focusCover(last.id)
        } else {
            endInteraction()
        }
        updateStatus()
    }

    private func setEditing(_ editing: Bool, on panel: OverlayPanel) {
        panel.ignoresMouseEvents = !editing
        panel.acceptsKeyFocus = editing
        if let surface = panel.contentView as? DesktopCoverSurface {
            surface.editing = editing
            if !editing { surface.selected = false }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.shouldCancelInteraction(event) else { return event }
            // AppKit dispatches local event monitors on the main thread.
            MainActor.assumeIsolated { self?.cancelInteraction() }
            return nil
        }
    }

    nonisolated static func shouldCancelInteraction(_ event: NSEvent) -> Bool {
        event.keyCode == 53 && event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    private func cancelInteraction() {
        endInteraction()
        updateStatus()
    }

    private func endInteraction() {
        let hadInteraction = isSelecting || isEditing
        isSelecting = false
        isEditing = false
        selectedCoverID = nil
        selectionPanels.forEach { $0.close() }
        selectionPanels.removeAll()
        covers.forEach { setEditing(false, on: $0.panel) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if hadInteraction, let priorKeyWindow, priorKeyWindow.isVisible { priorKeyWindow.makeKey() }
        priorKeyWindow = nil
    }

    private func installEmergencyBlankets() {
        // Present replacements first: a display change must not open a visible protection gap.
        let replacements = NSScreen.screens.map { screen in
            let panel = makePanel(frame: screen.frame, level: emergencyLevel, opaque: true)
            panel.title = "ShareSafe — emergency cover"
            panel.setAccessibilityLabel("ShareSafe emergency cover. Use Restore desktop to reveal your display.")
            // Recovery must remain possible when a global shortcut cannot be registered.
            panel.ignoresMouseEvents = false
            let surface = EmergencySurface(frame: CGRect(origin: .zero, size: screen.frame.size))
            surface.onRestore = { [weak self] in
                guard let self, self.emergencyCovered else { return }
                self.toggleEmergencyCover()
            }
            panel.contentView = surface
            panel.orderFrontRegardless()
            return panel
        }
        emergencyPanels.forEach { $0.close() }
        emergencyPanels = replacements
    }

    private func screensChanged() {
        guard !stopped else { return }
        let current = NSScreen.screens.compactMap(Display.init)
        let changed = current.count != displays.count || current.contains { !displays.contains($0) }
        guard changed else { return }
        displays = current
        if emergencyCovered || !covers.isEmpty {
            installEmergencyBlankets()
            emergencyCovered = true
            needsDisplayReview = true
            endInteraction()
            lastError = "Displays changed. All connected displays are covered. Restore the desktop, then review your areas before sharing."
            status = "Displays changed — emergency cover on. Review your areas."
            // Keep session records, including disconnected displays, until an explicit removal.
            // AppKit must not relocate a cover onto another display after a disconnect.
            for cover in covers {
                cover.panel.setFrame(cover.frame, display: false)
                if current.contains(where: { $0.id == cover.displayID }) {
                    cover.panel.orderFrontRegardless()
                } else {
                    cover.panel.orderOut(nil)
                }
            }
        } else if isSelecting {
            endInteraction()
            status = "Displays changed. Select the area again."
        }
    }

    private func updateStatus() {
        if emergencyCovered {
            status = lastError == nil ? "Emergency cover on — all displays hidden" : "Displays changed — emergency cover on. Review your areas."
        } else if isEditing {
            status = "Click or Tab to select. Arrows move; Shift moves faster. Delete removes. Escape finishes."
        } else if needsDisplayReview {
            status = "Displays changed — review hidden areas before sharing"
        } else {
            status = regionCount == 0 ? "Ready to hide an area" : "\(regionCount) \(regionCount == 1 ? "area" : "areas") hidden"
        }
    }
}

@MainActor
private final class OverlayPanel: NSPanel {
    var acceptsKeyFocus = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
private class BlackSurface: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
    }
}

@MainActor
private final class SelectionSurface: NSView {
    var screenFrame: CGRect = .zero
    var onCommit: ((CGRect?) -> Void)?
    var onCancel: (() -> Void)?
    private var dragStart: CGPoint?
    private var endpoint: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()
        if dragStart == nil {
            let text = "Drag to blur an area  ·  Esc cancels\nClick the ShareSafe menu-bar icon to add more. Right-click it for controls."
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
            let width = min(580, max(0, bounds.width - 32))
            let hint = CGRect(x: bounds.midX - width / 2, y: bounds.maxY - 120, width: width, height: 70)
            NSColor.black.withAlphaComponent(0.88).setFill()
            NSBezierPath(roundedRect: hint, xRadius: 12, yRadius: 12).fill()
            (text as NSString).draw(in: hint.insetBy(dx: 16, dy: 15), withAttributes: attributes)
        }
        guard let dragStart, let endpoint,
              let selected = OverlayGeometry.selection(start: dragStart, end: endpoint, in: screenFrame) else { return }
        let local = selected.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        NSColor.systemMint.withAlphaComponent(0.13).setFill()
        local.fill()
        NSColor.systemMint.setStroke()
        let outline = NSBezierPath(rect: local.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.makeKey()
        window.makeFirstResponder(self)
        dragStart = window.convertPoint(toScreen: event.locationInWindow)
        endpoint = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        endpoint = window.convertPoint(toScreen: event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart, let window else { return }
        let endpoint = window.convertPoint(toScreen: event.locationInWindow)
        let rectangle = OverlayGeometry.selection(start: dragStart, end: endpoint, in: screenFrame)
        onCommit?(rectangle)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
private final class EmergencySurface: BlackSurface {
    var onRestore: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let heading = NSTextField(labelWithString: "All displays hidden")
        heading.font = .systemFont(ofSize: 26, weight: .semibold)
        heading.textColor = .white
        heading.alignment = .center
        let instruction = NSTextField(wrappingLabelWithString: "Restore desktop, then review your hidden areas before sharing.")
        instruction.font = .systemFont(ofSize: 15)
        instruction.textColor = .lightGray
        instruction.alignment = .center
        let button = RestoreButton(title: "Restore desktop", target: self, action: #selector(restore))
        button.bezelStyle = .rounded
        button.bezelColor = .systemMint
        button.font = .systemFont(ofSize: 16, weight: .semibold)
        button.setAccessibilityLabel("Restore desktop")
        button.setAccessibilityHelp("Remove emergency blankets. Ordinary area covers remain in place.")
        for view in [heading, instruction, button] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.centerXAnchor.constraint(equalTo: centerXAnchor),
            heading.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 45),
            heading.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            instruction.centerXAnchor.constraint(equalTo: centerXAnchor),
            instruction.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            instruction.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            instruction.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            instruction.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 24),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 172),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func restore() { onRestore?() }
}

@MainActor
private final class RestoreButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
