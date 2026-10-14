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
        let controller = DesktopOverlayController(readWindows: { snapshot })
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
        let controller = DesktopOverlayController(readWindows: { snapshot })
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
        let controller = DesktopOverlayController(readWindows: { snapshot })
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
        let controller = DesktopOverlayController(readWindows: { snapshot })
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
        let controller = DesktopOverlayController(readWindows: { snapshot })
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
}
