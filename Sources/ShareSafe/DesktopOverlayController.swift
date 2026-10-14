import AppKit
import Combine
import ShareSafeCore

/// Session-only blur or solid windows. These protect captures that include desktop overlay windows;
/// they cannot alter another application's individually captured window or browser tab.
@MainActor
final class DesktopOverlayController: ObservableObject {
    @Published var maskStyle: MaskStyle = .blur
    @Published private(set) var regionCount = 0
    @Published private(set) var visibleRegionCount = 0
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
        var anchor: DesktopWindowAnchor
        let style: MaskStyle
        var frame: CGRect
        var panels: [OverlayPanel] = []
        var visibleFragments: [CGRect] = []
    }

    private var covers: [Cover] = []
    private var selectedCoverID: UUID?
    private var selectionPanels: [OverlayPanel] = []
    private var emergencyPanels: [OverlayPanel] = []
    private var displays: [Display] = []
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var trackingTask: Task<Void, Never>?
    private let readWindows: () -> DesktopWindowScope
    private var windowScope = DesktopWindowScope(windows: [])
    private var selectionWindow: DesktopWindow?
    private var keyMonitor: Any?
    private weak var priorKeyWindow: NSWindow?
    private var stopped = false
    private var needsDisplayReview = false

    private var editableCovers: [Cover] {
        covers.filter { !$0.visibleFragments.isEmpty }
    }

    init(readWindows: (() -> DesktopWindowScope)? = nil) {
        self.readWindows = readWindows ?? {
            DesktopWindowScope.read(primaryTop: NSScreen.screens.first?.frame.maxY ?? 0,
                excludingProcessID: ProcessInfo.processInfo.processIdentifier)
        }
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
                    for panel in cover.panels {
                        (panel.contentView as? DesktopCoverSurface)?.reduceTransparency = reduce
                    }
                }
            }
        }

        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if notification.name == NSWorkspace.didActivateApplicationNotification,
                       let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                       app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                        self.endInteraction()
                    }
                    self.refreshWindowScope()
                }
            })
        }
        // Window movement/resize has no permission-free cross-app notification.
        // Query only while areas exist; read metadata rather than capturing pixels.
        trackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, !self.covers.isEmpty { self.refreshWindowScope() }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func refreshWindowScope() {
        guard !stopped else { return }
        windowScope = readWindows()
        reconcileCovers()
    }

    private func reconcileCovers() {
        let keyPanel = NSApp.keyWindow
        let focusedCoverID = covers.first { cover in cover.panels.contains { $0 === keyPanel } }?.id
        var visible = 0
        for index in covers.indices {
            if let source = windowScope.window(for: covers[index].anchor.identity) {
                covers[index].frame = covers[index].anchor.rectangle(in: source.frame)
            }
            let fragments = windowScope.visibleFragments(for: covers[index].anchor).flatMap { frame in
                displays.compactMap { OverlayGeometry.clipped(frame, to: $0.frame) }
            }
            covers[index].visibleFragments = fragments
            if !fragments.isEmpty { visible += 1 }
            while covers[index].panels.count < fragments.count {
                covers[index].panels.append(makeCoverPanel(id: covers[index].id, style: covers[index].style))
            }
            for (part, panel) in covers[index].panels.enumerated() {
                guard part < fragments.count else {
                    setEditing(false, on: panel)
                    panel.orderOut(nil)
                    continue
                }
                if panel.frame != fragments[part] { panel.setFrame(fragments[part], display: true) }
                setEditing(isEditing, on: panel)
                (panel.contentView as? DesktopCoverSurface)?.selected = covers[index].id == selectedCoverID
                if !panel.isVisible { panel.orderFrontRegardless() }
            }
        }
        if visibleRegionCount != visible { visibleRegionCount = visible }
        if isEditing, !editableCovers.contains(where: { $0.id == selectedCoverID }) {
            if let next = editableCovers.last { focusCover(next.id) }
            else { endInteraction() }
        } else if isEditing, focusedCoverID == selectedCoverID, let selectedCoverID,
                  let keyPanel, !keyPanel.isVisible {
            // An occlusion change may pool the focused fragment while another
            // fragment of the same logical area remains. Keep its keys working.
            focusCover(selectedCoverID)
        }
        if !isSelecting { updateStatus() }
    }

    func beginSelection() {
        guard !stopped else { return }
        guard !emergencyCovered else {
            status = "Emergency cover is on. Turn it off to select an area."
            return
        }
        endInteraction()
        refreshWindowScope()
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
            view.onBegin = { [weak self] point in
                guard let self else { return }
                self.refreshWindowScope()
                self.selectionWindow = self.windowScope.target(at: point)
            }
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
        refreshWindowScope()
        guard let last = editableCovers.last else {
            status = covers.isEmpty ? "Hide an area before editing." :
                "Show a protected window to edit its areas."
            return
        }
        priorKeyWindow = NSApp.keyWindow
        isEditing = true
        installKeyMonitor()
        for cover in editableCovers {
            for panel in cover.panels where panel.isVisible { setEditing(true, on: panel) }
        }
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
            for panel in item.panels {
                (panel.contentView as? DesktopCoverSurface)?.selected = item.id == id
            }
        }
        if let panel = cover.panels.first(where: { $0.isVisible }) {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
        }
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
        cover.panels.forEach { $0.close() }
        regionCount = covers.count
        reconcileCovers()
        if covers.isEmpty { endInteraction() }
        updateStatus()
    }

    func removeAll() {
        guard !stopped, !emergencyCovered else { return }
        endInteraction()
        covers.forEach { $0.panels.forEach { $0.close() } }
        covers.removeAll()
        regionCount = 0
        visibleRegionCount = 0
        needsDisplayReview = false
        lastError = nil
        updateStatus()
    }

    func toggleEmergencyCover() {
        guard !stopped else { return }
        if emergencyCovered {
            // Reconcile window positions before uncovering the desktop.
            refreshWindowScope()
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
        trackingTask?.cancel()
        trackingTask = nil
        endInteraction()
        covers.forEach { $0.panels.forEach { $0.close() } }
        emergencyPanels.forEach { $0.close() }
        covers.removeAll()
        emergencyPanels.removeAll()
        regionCount = 0
        visibleRegionCount = 0
        emergencyCovered = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
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
        refreshWindowScope()
        guard let selected = selectionWindow,
              let source = windowScope.window(for: selected.identity),
              let clipped = OverlayGeometry.clipped(rectangle, to: display.frame),
              let anchor = DesktopWindowAnchor(window: source, rectangle: clipped) else {
            lastError = "Start your drag inside an app window. The area must overlap that window."
            return
        }
        let id = UUID()
        covers.append(Cover(id: id, anchor: anchor, style: maskStyle, frame: anchor.rectangle(in: source.frame)))
        regionCount = covers.count
        reconcileCovers()
        if !needsDisplayReview { lastError = nil }
    }

    private func makeCoverPanel(id: UUID, style: MaskStyle) -> OverlayPanel {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let panel = makePanel(frame: frame, level: coverLevel, opaque: style == .solid || reduceTransparency)
        panel.ignoresMouseEvents = true
        panel.title = "ShareSafe — hidden area"
        panel.setAccessibilityLabel("ShareSafe protected area")
        let surface = DesktopCoverSurface(frame: CGRect(origin: .zero, size: frame.size),
                                          style: style, reduceTransparency: reduceTransparency)
        surface.setAccessibilityElement(true)
        surface.setAccessibilityRole(.group)
        surface.setAccessibilityLabel("Protected area. In edit mode, drag to move or right-click to remove.")
        // A partially covered area can have several panels, but editing always
        // moves/selects/removes its one logical rectangle.
        surface.coverFrame = { [weak self] in self?.covers.first { $0.id == id }?.frame }
        surface.onMove = { [weak self] startFrame, delta in self?.moveCover(id, startFrame: startFrame, delta: delta) }
        surface.onSelect = { [weak self] in self?.focusCover(id) }
        surface.onSelectNext = { [weak self] reverse in self?.cycleCover(reverse: reverse) }
        surface.onNudge = { [weak self] delta in self?.nudgeCover(id, delta: delta) }
        surface.onRemove = { [weak self] in self?.removeCover(id) }
        surface.onCancel = { [weak self] in self?.cancelInteraction() }
        panel.contentView = surface
        return panel
    }

    private func moveCover(_ id: UUID, startFrame: CGRect, delta: CGVector) {
        guard isEditing, let index = covers.firstIndex(where: { $0.id == id }),
              let source = windowScope.window(for: covers[index].anchor.identity),
              let frame = OverlayGeometry.moved(startFrame, by: delta, in: source.frame),
              let anchor = DesktopWindowAnchor(window: source, rectangle: frame) else { return }
        covers[index].anchor = anchor
        reconcileCovers()
    }

    private func removeCover(_ id: UUID) {
        guard isEditing, let index = covers.firstIndex(where: { $0.id == id }) else { return }
        covers.remove(at: index).panels.forEach { $0.close() }
        regionCount = covers.count
        reconcileCovers()
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
            if surface.editing != editing { surface.editing = editing }
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

    func finishInteraction() {
        cancelInteraction()
    }

    private func endInteraction() {
        let hadInteraction = isSelecting || isEditing
        isSelecting = false
        selectionWindow = nil
        isEditing = false
        selectedCoverID = nil
        selectionPanels.forEach { $0.close() }
        selectionPanels.removeAll()
        covers.forEach { $0.panels.forEach { setEditing(false, on: $0) } }
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
            refreshWindowScope()
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
            status = regionCount == 0 ? "Ready to hide an area" :
                "\(visibleRegionCount) visible · \(regionCount) saved on their windows"
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
    var onBegin: ((CGPoint) -> Void)?
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
            let text = "Drag to blur an area  ·  Esc cancels\nUse the toolbar to add, move or clear areas."
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
        if let dragStart { onBegin?(dragStart) }
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
