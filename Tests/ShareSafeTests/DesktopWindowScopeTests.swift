import CoreGraphics
import Testing
@testable import ShareSafe

struct DesktopWindowScopeTests {
    private let source = DesktopWindow(identity: .init(windowID: 10, processID: 100),
                                       frame: CGRect(x: 100, y: 100, width: 500, height: 400), layer: 0)
    private let area = CGRect(x: 200, y: 200, width: 200, height: 100)

    private func other(_ id: UInt32 = 20, processID: Int32 = 200, frame: CGRect) -> DesktopWindow {
        DesktopWindow(identity: .init(windowID: id, processID: processID), frame: frame, layer: 0)
    }

    @Test func selectsTheWindowUnderTheDragRatherThanTheActiveApp() {
        let front = other(frame: CGRect(x: 400, y: 100, width: 300, height: 500))
        let scope = DesktopWindowScope(windows: [front, source])
        #expect(scope.target(at: CGPoint(x: 250, y: 250)) == source)
        #expect(scope.target(at: CGPoint(x: 450, y: 250)) == front)
        #expect(scope.target(at: CGPoint(x: -500, y: 250)) == nil)
    }

    @Test func menusAndFloatingWindowsDoNotBindAnAreaToTheWindowBehindThem() {
        let menu = DesktopWindow(identity: .init(windowID: 30, processID: 300), frame: area, layer: 24)
        #expect(DesktopWindowScope(windows: [menu, source]).target(at: area.origin) == nil)
    }

    @Test func switchingAppsHidesTheAreaAndReturningRestoresIt() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source, rectangle: area))
        let front = other(frame: source.frame)
        #expect(DesktopWindowScope(windows: [front, source]).visibleFragments(for: anchor).isEmpty)
        #expect(DesktopWindowScope(windows: [source, front]).visibleFragments(for: anchor) == [area])
    }

    @Test func anotherWindowFromTheSameAppDoesNotInheritTheBlur() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source, rectangle: area))
        let sibling = other(processID: source.identity.processID, frame: source.frame)
        #expect(DesktopWindowScope(windows: [sibling, source]).visibleFragments(for: anchor).isEmpty)
    }

    @Test func partialOcclusionKeepsVisibleSourceProtectedWithoutCoveringTheOtherWindow() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source, rectangle: area))
        let obstruction = other(frame: CGRect(x: 300, y: 200, width: 200, height: 100))
        #expect(DesktopWindowScope(windows: [obstruction, source]).visibleFragments(for: anchor)
                == [CGRect(x: 200, y: 200, width: 100, height: 100)])
        // The source remains protected even when another app is active beside it.
        let beside = other(frame: CGRect(x: 700, y: 100, width: 300, height: 400))
        #expect(DesktopWindowScope(windows: [beside, source]).visibleFragments(for: anchor) == [area])
    }

    @Test func closedMinimizedOrOffSpaceWindowsHaveNoOverlay() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source, rectangle: area))
        #expect(DesktopWindowScope(windows: []).visibleFragments(for: anchor).isEmpty)
        let replacement = other(10, processID: 999, frame: source.frame)
        #expect(DesktopWindowScope(windows: [replacement]).visibleFragments(for: anchor).isEmpty)
    }

    @Test func movementAcrossDisplaysKeepsTheOffsetFromTheWindowTopLeft() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source, rectangle: area))
        let moved = DesktopWindow(identity: source.identity,
                                  frame: CGRect(x: -900, y: 800, width: 500, height: 400), layer: 0)
        #expect(anchor.rectangle(in: moved.frame) == CGRect(x: -800, y: 900, width: 200, height: 100))
        #expect(DesktopWindowScope(windows: [moved]).visibleFragments(for: anchor)
                == [CGRect(x: -800, y: 900, width: 200, height: 100)])
    }

    @Test func resizeKeepsTopLeftOffsetAndClipsWithoutRescalingTheArea() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source, rectangle: area))
        let larger = CGRect(x: 100, y: 100, width: 700, height: 600)
        #expect(anchor.rectangle(in: larger) == CGRect(x: 200, y: 400, width: 200, height: 100))
        let smaller = DesktopWindow(identity: source.identity,
                                    frame: CGRect(x: 100, y: 100, width: 150, height: 250), layer: 0)
        #expect(DesktopWindowScope(windows: [smaller]).visibleFragments(for: anchor)
                == [CGRect(x: 200, y: 100, width: 50, height: 50)])
    }

    @Test func selectionIsClippedToItsWindowAndRejectsAnEmptyIntersection() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source,
            rectangle: CGRect(x: 50, y: 50, width: 200, height: 100)))
        #expect(anchor.rectangle(in: source.frame) == CGRect(x: 100, y: 100, width: 150, height: 50))
        #expect(DesktopWindowAnchor(window: source, rectangle: CGRect(x: -100, y: -100, width: 10, height: 10)) == nil)
    }

    @Test func multipleOccludersCannotLeaveBlurOverOtherWindows() throws {
        let anchor = try #require(DesktopWindowAnchor(window: source, rectangle: area))
        let obstructions = [
            other(20, frame: CGRect(x: 250, y: 225, width: 50, height: 50)),
            other(21, frame: CGRect(x: 280, y: 200, width: 40, height: 100))
        ]
        let fragments = DesktopWindowScope(windows: obstructions + [source]).visibleFragments(for: anchor)
        #expect(!fragments.isEmpty)
        for fragment in fragments {
            #expect(area.contains(fragment))
            for obstruction in obstructions {
                let intersection = fragment.intersection(obstruction.frame)
                #expect(intersection.isNull || intersection.isEmpty)
            }
        }
        #expect(fragments.reduce(0) { $0 + $1.width * $1.height } == 14_500)
    }

    @Test func coreGraphicsCoordinatesConvertOnVerticallyOffsetDisplays() {
        #expect(DesktopWindowScope.appKitFrame(CGRect(x: -900, y: -300, width: 600, height: 200), primaryTop: 900)
                == CGRect(x: -900, y: 1000, width: 600, height: 200))
    }
}
