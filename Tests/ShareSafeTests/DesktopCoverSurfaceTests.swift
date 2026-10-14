import AppKit
import Testing
import ShareSafeCore
@testable import ShareSafe

@MainActor
struct DesktopCoverSurfaceTests {
    private let frame = CGRect(x: 0, y: 0, width: 300, height: 200)

    @Test func blurUsesNativeBackdropWithoutCapturingPixels() {
        let surface = DesktopCoverSurface(frame: frame, style: .blur, reduceTransparency: false)
        #expect(surface.backdrop.blendingMode == .behindWindow)
        #expect(surface.backdrop.state == .active)
        #expect(surface.backdrop.material == .hudWindow)
        #expect(!surface.backdrop.isHidden && !surface.isOpaque)
        #expect(surface.hitTest(CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func reducedTransparencyKeepsTheAreaSolidAndCanRestoreBlur() {
        let surface = DesktopCoverSurface(frame: frame, style: .blur, reduceTransparency: true)
        #expect(surface.backdrop.isHidden && surface.isOpaque)
        surface.reduceTransparency = false
        #expect(!surface.backdrop.isHidden && !surface.isOpaque)
    }

    @Test func solidStyleDoesNotBecomeTransparentWhenAccessibilitySettingsChange() {
        let surface = DesktopCoverSurface(frame: frame, style: .solid, reduceTransparency: true)
        surface.reduceTransparency = false
        #expect(surface.backdrop.isHidden && surface.isOpaque)
    }

    @Test func editingRoutesEventsToTheCoverRatherThanItsMaterialSubview() {
        let surface = DesktopCoverSurface(frame: frame, style: .blur, reduceTransparency: false)
        surface.editing = true
        #expect(surface.hitTest(CGPoint(x: 10, y: 10)) === surface)
        #expect(surface.hitTest(CGPoint(x: 400, y: 400)) == nil)
        surface.editing = false
        #expect(surface.hitTest(CGPoint(x: 10, y: 10)) == nil)
    }

    private func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code))
    }

    @Test func arrowsMoveInScreenPointsAndShiftMakesLargerSteps() throws {
        let surface = DesktopCoverSurface(frame: frame, style: .blur, reduceTransparency: false)
        surface.editing = true
        var deltas: [CGVector] = []
        surface.onNudge = { deltas.append($0) }
        for code: UInt16 in [123, 124, 125, 126] {
            #expect(try surface.handleEditKey(key(code)))
        }
        #expect(try surface.handleEditKey(key(124, modifiers: .shift)))
        #expect(deltas == [CGVector(dx: -1, dy: 0), CGVector(dx: 1, dy: 0),
                           CGVector(dx: 0, dy: -1), CGVector(dx: 0, dy: 1), CGVector(dx: 10, dy: 0)])
    }

    @Test func deletionAndCyclingAreScopedToEditingAndDoNotStealModifiedAppKeys() throws {
        let surface = DesktopCoverSurface(frame: frame, style: .blur, reduceTransparency: false)
        var removed = 0
        var cycles: [Bool] = []
        surface.onRemove = { removed += 1 }
        surface.onSelectNext = { cycles.append($0) }
        #expect(try !surface.handleEditKey(key(51)))
        surface.editing = true
        #expect(try surface.handleEditKey(key(51)))
        #expect(try surface.handleEditKey(key(117)))
        #expect(try surface.handleEditKey(key(48)))
        #expect(try surface.handleEditKey(key(48, modifiers: .shift)))
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            #expect(try !surface.handleEditKey(key(51, modifiers: modifier)))
            #expect(try !surface.handleEditKey(key(124, modifiers: modifier)))
        }
        #expect(removed == 2 && cycles == [false, true])
    }

    @Test func escapeMonitorPreservesModifiedKeysBeforeTheyReachTheCover() throws {
        #expect(try DesktopOverlayController.shouldCancelInteraction(key(53)))
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            #expect(try !DesktopOverlayController.shouldCancelInteraction(key(53, modifiers: modifier)))
        }
        #expect(try !DesktopOverlayController.shouldCancelInteraction(key(51)))
    }
}
