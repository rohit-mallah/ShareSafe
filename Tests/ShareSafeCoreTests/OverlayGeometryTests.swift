import CoreGraphics
import Testing
@testable import ShareSafeCore

struct OverlayGeometryTests {
    @Test func selectionOnNegativeOriginDisplayPreservesGlobalCoordinates() {
        let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        #expect(OverlayGeometry.selection(
            start: CGPoint(x: -100, y: 800), end: CGPoint(x: -1700, y: -100), in: display
        ) == CGRect(x: -1700, y: -100, width: 1600, height: 900))
    }

    @Test func selectionOnVerticallyStackedDisplayClipsToItsOwnEdges() {
        let display = CGRect(x: 100, y: 900, width: 1200, height: 1600)
        #expect(OverlayGeometry.selection(
            start: CGPoint(x: 400, y: 1200), end: CGPoint(x: -1000, y: 4000), in: display
        ) == CGRect(x: 100, y: 1200, width: 300, height: 1300))
    }

    @Test func dragMustBeginOnOwningDisplayAndExceedMinimumOnBothAxes() {
        let display = CGRect(x: -100, y: 200, width: 300, height: 300)
        #expect(OverlayGeometry.selection(start: .zero, end: CGPoint(x: 100, y: 300), in: display) == nil)
        #expect(OverlayGeometry.selection(start: CGPoint(x: 0, y: 250), end: CGPoint(x: 2.9, y: 400), in: display) == nil)
        #expect(OverlayGeometry.selection(start: CGPoint(x: 0, y: 250), end: CGPoint(x: 100, y: 252.9), in: display) == nil)
        #expect(OverlayGeometry.selection(start: CGPoint(x: 0, y: 250), end: CGPoint(x: 3, y: 253), in: display) == CGRect(x: 0, y: 250, width: 3, height: 3))
    }

    @Test func selectionRejectsNonfiniteAndEmptyInput() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(OverlayGeometry.selection(start: .zero, end: CGPoint(x: CGFloat.nan, y: 10), in: display) == nil)
        #expect(OverlayGeometry.selection(start: CGPoint(x: CGFloat.infinity, y: 0), end: .zero, in: display) == nil)
        #expect(OverlayGeometry.selection(start: .zero, end: CGPoint(x: 10, y: 10), in: .zero) == nil)
        #expect(OverlayGeometry.selection(start: .zero, end: CGPoint(x: 10, y: 10), in: display, minimumSize: 0) == nil)
    }

    @Test func clippingUsesGlobalCoordinatesAndRejectsDisjointOrTouchingAreas() {
        let display = CGRect(x: -1600, y: 900, width: 1600, height: 1200)
        #expect(OverlayGeometry.clipped(CGRect(x: -1700, y: 850, width: 400, height: 300), to: display)
            == CGRect(x: -1600, y: 900, width: 300, height: 250))
        #expect(OverlayGeometry.clipped(CGRect(x: 0, y: 900, width: 100, height: 100), to: display) == nil)
        #expect(OverlayGeometry.clipped(CGRect(x: 100, y: 900, width: 100, height: 100), to: display) == nil)
        #expect(OverlayGeometry.clipped(CGRect(x: -1000, y: 1000, width: -100, height: 100), to: display) == nil)
    }

    @Test func movementClampsEveryEdgeWithoutShrinkingOrdinaryCovers() {
        let display = CGRect(x: -1600, y: -1000, width: 1600, height: 1000)
        let rectangle = CGRect(x: -800, y: -600, width: 200, height: 100)
        #expect(OverlayGeometry.moved(rectangle, by: CGVector(dx: -5000, dy: -5000), in: display)
            == CGRect(x: -1600, y: -1000, width: 200, height: 100))
        #expect(OverlayGeometry.moved(rectangle, by: CGVector(dx: 5000, dy: 5000), in: display)
            == CGRect(x: -200, y: -100, width: 200, height: 100))
    }

    @Test func verticalDisplayMovementUsesPointsAndKeepsOwningScreen() {
        let display = CGRect(x: 300, y: 1080, width: 900, height: 1600)
        #expect(OverlayGeometry.moved(CGRect(x: 500, y: 1500, width: 100, height: 200), by: CGVector(dx: 20, dy: -40), in: display)
            == CGRect(x: 520, y: 1460, width: 100, height: 200))
    }

    @Test func oversizedOrInvalidMovementIsHandledConservatively() {
        let display = CGRect(x: -100, y: 100, width: 300, height: 200)
        #expect(OverlayGeometry.moved(CGRect(x: -200, y: 50, width: 1000, height: 1000), by: .zero, in: display) == display)
        #expect(OverlayGeometry.moved(display, by: CGVector(dx: CGFloat.infinity, dy: 0), in: display) == nil)
        #expect(OverlayGeometry.moved(.zero, by: .zero, in: display) == nil)
        #expect(OverlayGeometry.moved(display, by: .zero, in: .zero) == nil)
    }
}
