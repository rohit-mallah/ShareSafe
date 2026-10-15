import ApplicationServices
import Foundation
import Testing
@testable import ShareSafe

/// Fictional AX objects and attributes; never reads an installed app's content.
private final class FixtureAXAccess: AXContentAccess, @unchecked Sendable {
    struct State {
        var trusted = true
        var role = kAXTextAreaRole
        var text = "🔒A fictional secret"
        var rangeFrame = CGRect(x: 135, y: 250, width: 150, height: 35)
        var textParameters = true
        var changedOwner = false
        var connected = true
        var invalid = false
        var parameters: [CFRange] = []
    }
    private let lock = NSLock()
    private var state = State()
    let target = AXUIElementCreateApplication(101)
    let inner = AXUIElementCreateApplication(102)
    let outer = AXUIElementCreateApplication(103)
    let window = AXUIElementCreateApplication(104)
    let otherWindow = AXUIElementCreateApplication(105)
    func update(_ change: (inout State) -> Void) { lock.withLock { change(&state) } }
    var isTrusted: Bool { lock.withLock { state.trusted } }
    var ranges: [CFRange] { lock.withLock { state.parameters } }
    func hitTest(processID: pid_t, point: CGPoint) throws -> AXUIElement? { target }
    func processID(of element: AXUIElement) throws -> pid_t { 100 }
    func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        try lock.withLock {
            if state.invalid { throw AXContentFailure.identity }
            let isTarget = CFEqual(element, target)
            if name == kAXRoleAttribute {
                return (isTarget ? state.role : CFEqual(element, window) || CFEqual(element, otherWindow) ? kAXWindowRole : kAXScrollAreaRole) as CFString
            }
            if name == kAXWindowAttribute { return state.changedOwner ? otherWindow : window }
            if name == kAXParentAttribute {
                if isTarget { return state.connected ? inner : nil }
                if CFEqual(element, inner) { return outer }
                if CFEqual(element, outer) { return window }
                return nil
            }
            if name == kAXValueAttribute { return isTarget ? state.text as CFString : nil }
            let frame: CGRect
            if isTarget { frame = CGRect(x: 130, y: 200, width: 300, height: 200) }
            else if CFEqual(element, inner) { frame = CGRect(x: 120, y: 180, width: 350, height: 300) }
            else if CFEqual(element, outer) { frame = CGRect(x: 110, y: 140, width: 400, height: 400) }
            else { frame = CGRect(x: 100, y: 100, width: 600, height: 600) }
            if name == kAXPositionAttribute {
                var point = frame.origin
                return AXValueCreate(.cgPoint, &point)
            }
            if name == kAXSizeAttribute {
                var size = frame.size
                return AXValueCreate(.cgSize, &size)
            }
            return nil
        }
    }
    func parameterNames(_ element: AXUIElement) throws -> [String]? {
        lock.withLock {
            state.textParameters ? [kAXRangeForPositionParameterizedAttribute, kAXBoundsForRangeParameterizedAttribute,
                kAXStringForRangeParameterizedAttribute] : nil
        }
    }
    func parameter(_ element: AXUIElement, _ name: String, value: CFTypeRef) throws -> CFTypeRef {
        try lock.withLock {
            if name == kAXRangeForPositionParameterizedAttribute {
                var point = CGPoint.zero
                guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { throw AXContentFailure.unavailable }
                var range = CFRange(location: point.x < 190 ? 0 : 2, length: point.x < 190 ? 2 : 1)
                return AXValueCreate(.cfRange, &range)!
            }
            var range = CFRange()
            guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { throw AXContentFailure.unavailable }
            state.parameters.append(range)
            if name == kAXStringForRangeParameterizedAttribute {
                let string = state.text as NSString
                guard range.location + range.length <= string.length else {
                    // Match the native AX error for an invalid retained range.
                    try SystemAXContentAccess.check(.illegalArgument)
                    throw AXContentFailure.unavailable
                }
                return string.substring(with: NSRange(location: range.location, length: range.length)) as CFString
            }
            if name == kAXBoundsForRangeParameterizedAttribute {
                var rect = state.rangeFrame
                return AXValueCreate(.cgRect, &rect)!
            }
            throw AXContentFailure.unavailable
        }
    }
}

struct AXContentReaderTests {
    private var window: DesktopWindow {
        .init(identity: .init(windowID: 10, processID: 100), frame: CGRect(x: 100, y: 300, width: 600, height: 600), layer: 0)
    }
    private var selection: CGRect { CGRect(x: 140, y: 700, width: 100, height: 30) }
    private func context(_ id: UUID) -> DesktopContentContext { .init(id: id, window: window, primaryTop: 1000) }

    @Test func textRangesUseUTF16AndFollowScrollThroughNestedViewports() async throws {
        let access = FixtureAXAccess()
        let reader = AXContentReader(access: access, sourceMatches: { _ in true })
        let id = UUID()
        let first = await reader.capture(id: id, rectangle: selection, window: window, primaryTop: 1000)
        guard case .visible(let initial) = first else { Issue.record("Expected a supported text range: \(first)"); return }
        #expect(initial.area == CGRect(x: 135, y: 715, width: 150, height: 35))
        #expect(access.ranges.allSatisfy { $0.location == 0 && $0.length == 3 })
        access.update { $0.rangeFrame.origin.y = 450 }
        let results = await reader.refresh([context(id)])
        guard case .visible(let scrolled) = try #require(results.first?.1) else { Issue.record("Expected clipped text"); return }
        #expect(scrolled.area == CGRect(x: 135, y: 515, width: 150, height: 35))
        #expect(scrolled.viewport == CGRect(x: 135, y: 520, width: 150, height: 30))
        access.update { $0.rangeFrame.origin.y = 900 }
        #expect(await reader.refresh([context(id)]).first?.1 == .offscreen)
        access.update { $0.rangeFrame.origin.y = 250 }
        #expect(await reader.refresh([context(id)]).first?.1 == first)
    }

    @Test func changedTextLatchesLossEvenDuringAWindowMove() async {
        let access = FixtureAXAccess()
        let reader = AXContentReader(access: access, sourceMatches: { _ in false })
        let id = UUID()
        _ = await reader.capture(id: id, rectangle: selection, window: window, primaryTop: 1000)
        access.update { $0.text = "XXA replacement row" }
        #expect(await reader.refresh([context(id)]).first?.1 == .lost)
        access.update { $0.text = "🔒A fictional secret" }
        #expect(await reader.refresh([context(id)]).first?.1 == .lost)
    }

    @Test func shortenedDocumentLatchesInvalidRangeEvenDuringAWindowMove() async {
        let access = FixtureAXAccess()
        let reader = AXContentReader(access: access, sourceMatches: { _ in false })
        let id = UUID()
        _ = await reader.capture(id: id, rectangle: selection, window: window, primaryTop: 1000)
        access.update { $0.text = "x" }
        #expect(await reader.refresh([context(id)]).first?.1 == .lost)
        access.update { $0.text = "🔒A fictional secret" }
        #expect(await reader.refresh([context(id)]).first?.1 == .lost)
    }

    @Test func revokedTrustLatchesLossEvenDuringAWindowMove() async {
        let access = FixtureAXAccess()
        let reader = AXContentReader(access: access, sourceMatches: { _ in false })
        let id = UUID()
        _ = await reader.capture(id: id, rectangle: selection, window: window, primaryTop: 1000)
        access.update { $0.trusted = false }
        #expect(await reader.refresh([context(id)]).first?.1 == .lost)
        access.update { $0.trusted = true }
        #expect(await reader.refresh([context(id)]).first?.1 == .lost)
    }

    @Test(arguments: ["owner", "parent", "invalid"])
    func changedOwnershipOrDetachedContentCannotAttachToAnotherWindow(change: String) async {
        let access = FixtureAXAccess()
        let reader = AXContentReader(access: access, sourceMatches: { _ in false })
        let id = UUID()
        _ = await reader.capture(id: id, rectangle: selection, window: window, primaryTop: 1000)
        access.update {
            if change == "owner" { $0.changedOwner = true }
            if change == "parent" { $0.connected = false }
            if change == "invalid" { $0.invalid = true }
        }
        #expect(await reader.refresh([context(id)]).first?.1 == .lost)
    }

    @Test func unsupportedTextRangeAndAnonymousGroupsAreRejected() async {
        let access = FixtureAXAccess()
        let reader = AXContentReader(access: access)
        access.update { $0.textParameters = false }
        #expect(await reader.capture(id: UUID(), rectangle: selection, window: window, primaryTop: 1000) == .unsupported)
        access.update { $0.role = kAXGroupRole }
        #expect(await reader.capture(id: UUID(), rectangle: selection, window: window, primaryTop: 1000) == .unsupported)
    }

    @Test func mutableControlKeepsItsIdentityWhenItsValueChanges() async {
        let access = FixtureAXAccess()
        access.update { $0.textParameters = false; $0.role = kAXTextFieldRole }
        let reader = AXContentReader(access: access)
        let id = UUID()
        let initial = await reader.capture(id: id, rectangle: selection, window: window, primaryTop: 1000)
        access.update { $0.text = "edited value" }
        #expect(await reader.refresh([context(id)]).first?.1 == initial)
        await reader.remove(id)
        #expect(await reader.refresh([context(id)]).first?.1 == .unsupported)
    }
}
