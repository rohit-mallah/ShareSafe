import AppKit
import Testing
@testable import ShareSafe

@MainActor
@Suite(.serialized)
struct DesktopOverlayControllerTests {
    private func source() throws -> DesktopWindow {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        return DesktopWindow(identity: .init(windowID: 10, processID: 100),
                             frame: screen.frame.insetBy(dx: 100, dy: 100), layer: 0)
    }

    private var visiblePanels: [NSWindow] {
        NSApp.windows.filter { $0.title == "ShareSafe — hidden area" && $0.isVisible }
    }

    private func draw(_ area: CGRect, in controller: DesktopOverlayController) throws {
        controller.beginSelection()
        let panel = try #require(NSApp.windows.first {
            $0.title == "ShareSafe — select an area" && $0.isVisible && $0.frame.contains(area.origin)
        })
        let surface = try #require(panel.contentView)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        surface.mouseDown(with: try event(.leftMouseDown, area.origin))
        surface.mouseUp(with: try event(.leftMouseUp, CGPoint(x: area.maxX, y: area.maxY)))
    }

    @Test func realWindowMetadataPreservesIdentityAndBoundsAndExcludesOurOwnPanels() async throws {
        let original = try source()
        let frame = original.frame.insetBy(dx: 100, dy: 100)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.orderFrontRegardless()
        window.display()
        let primaryTop = try #require(NSScreen.screens.first?.frame.maxY)
        let identity = DesktopWindowIdentity(windowID: UInt32(window.windowNumber),
                                            processID: ProcessInfo.processInfo.processIdentifier)
        var included = DesktopWindowScope.read(primaryTop: primaryTop, excludingProcessID: -1)
        // WindowServer publishes a newly ordered window asynchronously.
        for _ in 0..<50 {
            if included.window(for: identity) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
            included = DesktopWindowScope.read(primaryTop: primaryTop, excludingProcessID: -1)
        }
        #expect(included.window(for: identity)?.frame == window.frame)
        let excluded = DesktopWindowScope.read(primaryTop: primaryTop, excludingProcessID: identity.processID)
        #expect(excluded.window(for: identity) == nil)
    }

    @Test func panelsDisappearUnderAnotherAppAndReturnAtTheMovedWindowPosition() throws {
        let original = try source()
        let area = original.frame.insetBy(dx: 100, dy: 100)
        var snapshot = DesktopWindowScope(windows: [original])
        let controller = DesktopOverlayController(followsContent: false, readWindows: { snapshot })
        defer { controller.stop() }
        try draw(area, in: controller)
        #expect(controller.regionCount == 1 && controller.visibleRegionCount == 1)
        #expect(visiblePanels.map(\.frame) == [area])
        let other = DesktopWindow(identity: .init(windowID: 20, processID: 200), frame: original.frame, layer: 0)
        snapshot = DesktopWindowScope(windows: [other, original])
        controller.refreshWindowScope()
        #expect(controller.regionCount == 1 && controller.visibleRegionCount == 0)
        #expect(visiblePanels.isEmpty)
        let moved = DesktopWindow(identity: original.identity, frame: original.frame.offsetBy(dx: 20, dy: 30), layer: 0)
        snapshot = DesktopWindowScope(windows: [moved, other])
        controller.refreshWindowScope()
        #expect(visiblePanels.map(\.frame) == [area.offsetBy(dx: 20, dy: 30)])
    }

    @Test func splitPanelsRemainOneEditableAreaAndDeleteRemovesEveryPiece() throws {
        let original = try source()
        let area = CGRect(x: original.frame.minX + 50, y: original.frame.minY + 50, width: 200, height: 150)
        let obstruction = DesktopWindow(identity: .init(windowID: 20, processID: 100),
            frame: area.insetBy(dx: 50, dy: 50), layer: 0)
        var snapshot = DesktopWindowScope(windows: [original])
        let controller = DesktopOverlayController(followsContent: false, readWindows: { snapshot })
        defer { controller.stop() }
        try draw(area, in: controller)
        snapshot = DesktopWindowScope(windows: [obstruction, original])
        controller.refreshWindowScope()
        #expect(visiblePanels.count == 4)
        #expect(controller.regionCount == 1 && controller.visibleRegionCount == 1)
        controller.toggleEditing()
        #expect(controller.isEditing)
        let surface = try #require(visiblePanels.first?.contentView as? DesktopCoverSurface)
        #expect(surface.coverFrame?() == area)
        let right = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 124))
        #expect(surface.handleEditKey(right))
        #expect(surface.coverFrame?() == area.offsetBy(dx: 10, dy: 0))
        controller.removeSelected()
        #expect(controller.regionCount == 0 && controller.visibleRegionCount == 0)
        #expect(!controller.isEditing && visiblePanels.isEmpty)
    }

    @Test func disappearingWindowEndsEditingAndRestoredPanelsAreClickThrough() throws {
        let original = try source()
        var snapshot = DesktopWindowScope(windows: [original])
        let controller = DesktopOverlayController(followsContent: false, readWindows: { snapshot })
        defer { controller.stop() }
        try draw(original.frame.insetBy(dx: 100, dy: 100), in: controller)
        controller.toggleEditing()
        #expect(controller.isEditing)
        snapshot = DesktopWindowScope(windows: [])
        controller.refreshWindowScope()
        #expect(!controller.isEditing && visiblePanels.isEmpty)
        snapshot = DesktopWindowScope(windows: [original])
        controller.refreshWindowScope()
        #expect(visiblePanels.count == 1 && visiblePanels.allSatisfy(\.ignoresMouseEvents))
    }

    @Test func mergingFragmentsKeepsKeyboardFocusOnTheSelectedLogicalArea() throws {
        let original = try source()
        let area = CGRect(x: original.frame.minX + 50, y: original.frame.minY + 50, width: 200, height: 150)
        let obstruction = DesktopWindow(identity: .init(windowID: 20, processID: 200),
                                        frame: area.insetBy(dx: 50, dy: 50), layer: 0)
        var snapshot = DesktopWindowScope(windows: [original])
        let controller = DesktopOverlayController(followsContent: false, readWindows: { snapshot })
        defer { controller.stop() }
        try draw(area, in: controller)
        snapshot = DesktopWindowScope(windows: [obstruction, original])
        controller.refreshWindowScope()
        controller.toggleEditing()
        let removedFragment = try #require(visiblePanels.first {
            $0.frame.minX == area.maxX - 50 && $0.frame.height == area.height
        })
        removedFragment.makeKeyAndOrderFront(nil)
        removedFragment.makeFirstResponder(removedFragment.contentView)
        #expect(removedFragment.isKeyWindow)
        snapshot = DesktopWindowScope(windows: [original])
        controller.refreshWindowScope()
        #expect(controller.isEditing && visiblePanels.count == 1)
        #expect(visiblePanels.first?.isKeyWindow == true)
        #expect((removedFragment.contentView as? DesktopCoverSurface)?.editing == false)
    }

    @Test func emergencyRecoveryRepositionsAreasBeforeRevealingTheDesktop() throws {
        let original = try source()
        let area = original.frame.insetBy(dx: 100, dy: 100)
        var snapshot = DesktopWindowScope(windows: [original])
        let controller = DesktopOverlayController(followsContent: false, readWindows: { snapshot })
        defer { controller.stop() }
        try draw(area, in: controller)
        controller.toggleEmergencyCover()
        controller.undo()
        controller.removeAll()
        #expect(controller.emergencyCovered && controller.regionCount == 1)
        let moved = DesktopWindow(identity: original.identity, frame: original.frame.offsetBy(dx: 20, dy: 30), layer: 0)
        snapshot = DesktopWindowScope(windows: [moved])
        controller.toggleEmergencyCover()
        #expect(!controller.emergencyCovered)
        #expect(visiblePanels.map(\.frame) == [area.offsetBy(dx: 20, dy: 30)])
    }

    @Test func toolbarShowsWithoutStartingSelectionAndItsPrimaryButtonFinishesDrawing() throws {
        let original = try source()
        let controller = DesktopOverlayController(followsContent: false, readWindows: { DesktopWindowScope(windows: [original]) })
        let toolbar = DesktopToolbarController(overlays: controller)
        defer { toolbar.stop(); controller.stop() }
        toolbar.show()
        #expect(toolbar.panel.isVisible && !toolbar.panel.canBecomeKey && !toolbar.panel.canBecomeMain)
        #expect(!controller.isSelecting && controller.regionCount == 0)
        #expect(toolbar.panel.frame.height <= 64 && toolbar.panel.frame.width <= 500)
        #expect(NSScreen.screens.contains { $0.visibleFrame.contains(toolbar.panel.frame) })
        #expect(toolbar.primaryButton.acceptsFirstMouse(for: nil))
        #expect(!toolbar.editButton.isEnabled && !toolbar.undoButton.isEnabled && !toolbar.clearButton.isEnabled)
        toolbar.primaryButton.performClick(nil)
        #expect(controller.isSelecting && toolbar.primaryButton.title == "Done")
        #expect(toolbar.panel.isVisible && !toolbar.panel.isKeyWindow)
        toolbar.primaryButton.performClick(nil)
        #expect(!controller.isSelecting && toolbar.primaryButton.title == "Blur area")
    }

    @Test func hidingToolbarEndsEditingButKeepsAreasAndReopeningDoesNotEnrollAWindow() throws {
        let original = try source()
        let controller = DesktopOverlayController(followsContent: false, readWindows: { DesktopWindowScope(windows: [original]) })
        let toolbar = DesktopToolbarController(overlays: controller)
        defer { toolbar.stop(); controller.stop() }
        try draw(original.frame.insetBy(dx: 100, dy: 100), in: controller)
        toolbar.show()
        toolbar.editButton.performClick(nil)
        #expect(controller.isEditing && toolbar.editButton.title == "Remove")
        #expect(toolbar.primaryButton.title == "Done")
        #expect(visiblePanels.first?.isKeyWindow == true)
        toolbar.hideButton.performClick(nil)
        #expect(!toolbar.panel.isVisible && !controller.isEditing && !controller.isSelecting)
        #expect(controller.regionCount == 1 && visiblePanels.count == 1)
        #expect(visiblePanels.allSatisfy { $0.ignoresMouseEvents })
        toolbar.show()
        #expect(!controller.isSelecting && toolbar.primaryButton.title == "Blur area")
        toolbar.editButton.performClick(nil)
        toolbar.editButton.performClick(nil)
        #expect(controller.regionCount == 0 && !controller.isEditing && visiblePanels.isEmpty)
    }

    @Test func toolbarClearAndUndoRouteToTheExistingAreasAndEmergencyKeepsRestoreAvailable() throws {
        let original = try source()
        let area = original.frame.insetBy(dx: 100, dy: 100)
        let controller = DesktopOverlayController(followsContent: false, readWindows: { DesktopWindowScope(windows: [original]) })
        let toolbar = DesktopToolbarController(overlays: controller)
        defer { toolbar.stop(); controller.stop() }
        try draw(area, in: controller)
        try draw(area.insetBy(dx: 10, dy: 10), in: controller)
        toolbar.show()
        toolbar.undoButton.performClick(nil)
        #expect(controller.regionCount == 1)
        controller.toggleEmergencyCover()
        toolbar.refresh()
        #expect(toolbar.primaryButton.title == "Restore" && toolbar.primaryButton.isEnabled)
        #expect(!toolbar.editButton.isEnabled && !toolbar.undoButton.isEnabled && !toolbar.clearButton.isEnabled)
        toolbar.clearButton.performClick(nil)
        #expect(controller.emergencyCovered && controller.regionCount == 1)
        toolbar.primaryButton.performClick(nil)
        #expect(!controller.emergencyCovered && controller.regionCount == 1)
        toolbar.clearButton.performClick(nil)
        #expect(controller.regionCount == 0 && visiblePanels.isEmpty)
    }

    @Test func contentToolbarFitsItsControlsAndPermissionNotice() throws {
        let original = try source()
        let tracker = StubContentTracker()
        tracker.isTrusted = false
        let controller = DesktopOverlayController(readWindows: { DesktopWindowScope(windows: [original]) }, contentTracker: tracker)
        let toolbar = DesktopToolbarController(overlays: controller)
        defer { toolbar.stop(); controller.stop() }
        toolbar.show()
        toolbar.panel.contentView?.layoutSubtreeIfNeeded()
        #expect(toolbar.primaryButton.title == "Blur content")
        let buttons = [toolbar.primaryButton, toolbar.modeButton, toolbar.editButton, toolbar.undoButton, toolbar.clearButton, toolbar.hideButton]
        #expect(buttons.allSatisfy { !$0.hasAmbiguousLayout && $0.frame.width > 0 && $0.frame.height > 0 })
        for (left, right) in zip(buttons, buttons.dropFirst()) { #expect(left.frame.maxX <= right.frame.minX) }
        toolbar.primaryButton.performClick(nil)
        toolbar.panel.contentView?.layoutSubtreeIfNeeded()
        #expect(toolbar.panel.frame.height == 92 && toolbar.modeButton.isEnabled)
        #expect(!controller.isSelecting && tracker.requests == 1)
        controller.setContentFollowing(false)
        toolbar.refresh()
        #expect(toolbar.panel.frame.height == 56 && toolbar.primaryButton.title == "Blur area")
    }

    @Test func contentMovesWithScrollingAndLeavesAndReentersItsViewport() throws {
        let original = try source()
        let area = original.frame.insetBy(dx: 100, dy: 100)
        let tracker = StubContentTracker()
        let controller = DesktopOverlayController(readWindows: { DesktopWindowScope(windows: [original]) }, contentTracker: tracker)
        defer { controller.stop() }
        #expect(controller.followsContent)
        try draw(area, in: controller)
        let id = try #require(tracker.captured.last)
        // Initial binding covers the source while geometry is unknown.
        #expect(visiblePanels.map(\.frame) == [original.frame])
        #expect(controller.pausedContentCount == 1 && controller.editableRegionCount == 0)
        let scrolled = area.offsetBy(dx: 0, dy: 30)
        let viewport = CGRect(x: scrolled.minX, y: scrolled.minY, width: scrolled.width, height: scrolled.height - 20)
        tracker.publish(.visible(.init(area: scrolled, viewport: viewport, windowFrame: original.frame)), id: id)
        #expect(visiblePanels.map(\.frame) == [viewport])
        #expect(controller.pausedContentCount == 0 && controller.editableRegionCount == 1)
        tracker.publish(.offscreen, id: id)
        #expect(visiblePanels.isEmpty && controller.regionCount == 1)
        tracker.publish(.visible(.init(area: area, viewport: original.frame, windowFrame: original.frame)), id: id)
        #expect(visiblePanels.map(\.frame) == [area])
    }

    @Test func unavailableContentUsesSolidWindowCoverageAndRemainsUndoable() throws {
        let original = try source()
        let tracker = StubContentTracker()
        let controller = DesktopOverlayController(readWindows: { DesktopWindowScope(windows: [original]) }, contentTracker: tracker)
        let toolbar = DesktopToolbarController(overlays: controller)
        defer { toolbar.stop(); controller.stop() }
        try draw(original.frame.insetBy(dx: 100, dy: 100), in: controller)
        let id = try #require(tracker.captured.last)
        tracker.publish(.lost, id: id)
        #expect(visiblePanels.map(\.frame) == [original.frame])
        #expect(visiblePanels.allSatisfy { ($0.contentView as? DesktopCoverSurface)?.usesSolidCover == true && $0.ignoresMouseEvents })
        controller.toggleEditing()
        #expect(!controller.isEditing && controller.editableRegionCount == 0)
        toolbar.refresh()
        #expect(!toolbar.editButton.isEnabled && toolbar.undoButton.isEnabled && toolbar.clearButton.isEnabled)
        #expect(toolbar.panel.frame.height > 56)
        controller.undo()
        #expect(controller.regionCount == 0 && tracker.removed == [id] && visiblePanels.isEmpty)
    }

    @Test func contentSourceCanMinimizeAndMoveWithoutQueryingItsHiddenTarget() throws {
        let original = try source()
        let tracker = StubContentTracker()
        var snapshot = DesktopWindowScope(windows: [original])
        let controller = DesktopOverlayController(readWindows: { snapshot }, contentTracker: tracker)
        defer { controller.stop() }
        let area = original.frame.insetBy(dx: 100, dy: 100)
        try draw(area, in: controller)
        let id = try #require(tracker.captured.last)
        tracker.publish(.visible(.init(area: area, viewport: original.frame, windowFrame: original.frame)), id: id)
        snapshot = DesktopWindowScope(windows: [])
        controller.refreshWindowScope()
        #expect(visiblePanels.isEmpty && tracker.lastContexts.isEmpty)
        let moved = DesktopWindow(identity: original.identity, frame: original.frame.offsetBy(dx: 10, dy: 10), layer: 0)
        snapshot = DesktopWindowScope(windows: [moved])
        controller.refreshWindowScope()
        // Geometry for the old window location must never be shown on return.
        #expect(visiblePanels.map(\.frame) == [moved.frame])
        #expect(controller.pausedContentCount == 1 && tracker.lastContexts.map(\.id) == [id])
        tracker.publish(.visible(.init(area: area.offsetBy(dx: 10, dy: 10), viewport: moved.frame, windowFrame: moved.frame)), id: id)
        #expect(visiblePanels.map(\.frame) == [area.offsetBy(dx: 10, dy: 10)])
    }

    @Test func contentAndProtectiveCoversRespectOtherAppsAndSiblingWindows() throws {
        let original = try source()
        let area = original.frame.insetBy(dx: 100, dy: 100)
        let other = DesktopWindow(identity: .init(windowID: 20, processID: 100), frame: original.frame, layer: 0)
        var snapshot = DesktopWindowScope(windows: [original])
        let tracker = StubContentTracker()
        let controller = DesktopOverlayController(readWindows: { snapshot }, contentTracker: tracker)
        defer { controller.stop() }
        try draw(area, in: controller)
        let id = try #require(tracker.captured.last)
        tracker.publish(.visible(.init(area: area, viewport: original.frame, windowFrame: original.frame)), id: id)
        snapshot = DesktopWindowScope(windows: [other, original])
        controller.refreshWindowScope()
        #expect(visiblePanels.isEmpty)
        tracker.publish(.lost, id: id)
        #expect(visiblePanels.isEmpty)
        snapshot = DesktopWindowScope(windows: [original, other])
        controller.refreshWindowScope()
        #expect(visiblePanels.map(\.frame) == [original.frame])
    }

    @Test func permissionsAreRequestedOnlyForExplicitContentSelectionAndFixedAreasStayIndependent() throws {
        let original = try source()
        let tracker = StubContentTracker()
        tracker.isTrusted = false
        let controller = DesktopOverlayController(readWindows: { DesktopWindowScope(windows: [original]) }, contentTracker: tracker)
        defer { controller.stop() }
        #expect(tracker.requests == 0)
        controller.beginSelection()
        #expect(!controller.isSelecting && controller.lastError?.contains("Accessibility") == true && tracker.requests == 1)
        controller.setContentFollowing(false)
        try draw(original.frame.insetBy(dx: 100, dy: 100), in: controller)
        #expect(controller.regionCount == 1 && tracker.captured.isEmpty && tracker.requests == 1)
        controller.removeAll()
        controller.setContentFollowing(true)
        tracker.isTrusted = true
        try draw(original.frame.insetBy(dx: 100, dy: 100), in: controller)
        #expect(tracker.requests == 1 && tracker.captured.count == 1)
    }

    @Test func unsupportedContentIsReportedWithoutSilentlyCreatingAFixedArea() throws {
        let original = try source()
        let tracker = StubContentTracker()
        let controller = DesktopOverlayController(readWindows: { DesktopWindowScope(windows: [original]) }, contentTracker: tracker)
        defer { controller.stop() }
        try draw(original.frame.insetBy(dx: 100, dy: 100), in: controller)
        let id = try #require(tracker.captured.last)
        tracker.publish(.unsupported, id: id)
        #expect(controller.regionCount == 0 && visiblePanels.isEmpty && tracker.removed == [id])
        #expect(controller.lastError?.contains("cannot be followed") == true && controller.followsContent)
    }

    @Test func editingContentRebindsExplicitlyAndClearingOrStoppingReleasesEveryTarget() throws {
        let original = try source()
        let area = original.frame.insetBy(dx: 100, dy: 100)
        let tracker = StubContentTracker()
        let controller = DesktopOverlayController(readWindows: { DesktopWindowScope(windows: [original]) }, contentTracker: tracker)
        defer { controller.stop() }
        try draw(area, in: controller)
        let id = try #require(tracker.captured.last)
        tracker.publish(.visible(.init(area: area, viewport: original.frame, windowFrame: original.frame)), id: id)
        controller.toggleEditing()
        let surface = try #require(visiblePanels.first?.contentView as? DesktopCoverSurface)
        surface.onNudge?(CGVector(dx: 10, dy: 0))
        surface.onNudge?(CGVector(dx: 10, dy: 0))
        #expect(controller.isEditing && tracker.captured == [id])
        #expect(surface.coverFrame?() == area.offsetBy(dx: 20, dy: 0))
        controller.finishInteraction()
        let replacement = try #require(tracker.captured.last)
        #expect(replacement != id && tracker.removed == [id])
        #expect(tracker.rectangles.last == area.offsetBy(dx: 20, dy: 0))
        controller.removeAll()
        #expect(tracker.removed.contains(replacement) && controller.regionCount == 0)
        try draw(area, in: controller)
        let last = try #require(tracker.captured.last)
        controller.stop()
        #expect(tracker.removed.contains(last) && tracker.onChange == nil && visiblePanels.isEmpty)
    }

}


@MainActor
private final class StubContentTracker: DesktopContentTracking {
    var isTrusted = true
    var onChange: (() -> Void)?
    var requests = 0
    var captured: [UUID] = []
    var rectangles: [CGRect] = []
    var removed: [UUID] = []
    var lastContexts: [DesktopContentContext] = []
    private var states: [UUID: DesktopContentState] = [:]
    func requestAccessIfNeeded() { requests += 1 }
    func capture(rectangle: CGRect, window: DesktopWindow, primaryTop: CGFloat) -> UUID {
        let id = UUID()
        captured.append(id)
        rectangles.append(rectangle)
        states[id] = .pending
        return id
    }
    func state(for id: UUID) -> DesktopContentState { states[id] ?? .lost }
    func refresh(_ contexts: [DesktopContentContext]) { lastContexts = contexts }
    func remove(_ id: UUID) { removed.append(id); states.removeValue(forKey: id) }
    func publish(_ state: DesktopContentState, id: UUID) { states[id] = state; onChange?() }
}
