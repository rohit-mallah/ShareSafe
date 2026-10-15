import ApplicationServices
import Foundation
import ShareSafeCore

/// Owns retained AX objects on its serial actor executor. Any
/// text used for identity stay in memory; they are never logged or persisted.
actor AXContentReader: DesktopContentReading {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private struct TextIdentity {
        let range: CFRange
        let text: String
    }
    private struct Target {
        let element: AXUIElement
        let owner: DesktopWindowIdentity
        let ownerElement: AXUIElement
        let role: String
        let identifier: String?
        let value: String?
        let text: TextIdentity?
        var lost = false
    }
    private var targets: [UUID: Target] = [:]
    private var nextStart = 0
    private var deadline: TimeInterval = 0
    private let access: any AXContentAccess
    private let sourceMatches: @Sendable (DesktopContentContext) -> Bool

    init(access: any AXContentAccess = SystemAXContentAccess(),
         sourceMatches: (@Sendable (DesktopContentContext) -> Bool)? = nil) {
        self.access = access
        self.sourceMatches = sourceMatches ?? { Self.sourceStillMatches($0) }
    }

    func capture(id: UUID, rectangle: CGRect, window: DesktopWindow, primaryTop: CGFloat) -> DesktopContentState {
        deadline = ProcessInfo.processInfo.systemUptime + 0.25
        guard access.isTrusted else { return .unsupported }
        do {
            let point = CGPoint(x: rectangle.midX, y: primaryTop - rectangle.midY)
            try checkBudget()
            guard var element = try access.hitTest(processID: window.identity.processID, point: point) else { return .unsupported }
            // Hit-testing the application root ignores ShareSafe's selector.
            for _ in 0..<16 {
                let role = try string(element, kAXRoleAttribute)
                let frame = try bounds(element, primaryTop: primaryTop)
                if frame.insetBy(dx: -4, dy: -4).contains(rectangle),
                   let role, ![kAXWindowRole, kAXApplicationRole, kAXScrollAreaRole, "AXWebArea", kAXGroupRole].contains(role) {
                    guard try matchesWindow(element, window: window, primaryTop: primaryTop),
                          let owner = try elementAttribute(element, kAXWindowAttribute) else { return .unsupported }
                    let text = try textIdentity(element, rectangle: rectangle, primaryTop: primaryTop)
                    if role == kAXTextAreaRole && text == nil { return .unsupported }
                    let value = text == nil && !Self.mutableRoles.contains(role) ? try identityValue(element) : nil
                    guard text != nil || Self.mutableRoles.contains(role) || value != nil else { return .unsupported }
                    targets[id] = Target(element: element, owner: window.identity, ownerElement: owner, role: role,
                        identifier: try string(element, kAXIdentifierAttribute), value: value, text: text)
                    return try resolve(id, window: window, primaryTop: primaryTop)
                }
                guard let parent = try elementAttribute(element, kAXParentAttribute) else { return .unsupported }
                element = parent
            }
            return .unsupported
        } catch { return .unsupported }
    }

    func refresh(_ contexts: [DesktopContentContext]) -> [(UUID, DesktopContentState)] {
        deadline = ProcessInfo.processInfo.systemUptime + 0.12
        guard !contexts.isEmpty else { return [] }
        var results: [(UUID, DesktopContentState)] = []
        let start = nextStart % contexts.count
        for offset in contexts.indices {
            let context = contexts[(start + offset) % contexts.count]
            do {
                try checkBudget()
                let state = try resolve(context.id, window: context.window, primaryTop: context.primaryTop)
                results.append((context.id, state))
            } catch AXContentFailure.budget { break }
            catch AXContentFailure.identity {
                targets[context.id]?.lost = true
                results.append((context.id, .lost))
            } catch {
                // A source may have moved/minimized after the main-thread
                // snapshot was taken. That transient is not lost identity.
                if sourceMatches(context) {
                    targets[context.id]?.lost = true
                    results.append((context.id, .lost))
                } else { results.append((context.id, .pending)) }
            }
        }
        nextStart = (start + max(1, results.count)) % contexts.count
        return results
    }

    func remove(_ id: UUID) { targets.removeValue(forKey: id) }

    private func resolve(_ id: UUID, window: DesktopWindow, primaryTop: CGFloat) throws -> DesktopContentState {
        guard let target = targets[id] else { return .unsupported }
        guard !target.lost else { return .lost }
        guard access.isTrusted, target.owner == window.identity else { throw AXContentFailure.identity }
        guard let owner = try elementAttribute(target.element, kAXWindowAttribute),
              CFEqual(owner, target.ownerElement) else { throw AXContentFailure.identity }
        guard try string(target.element, kAXRoleAttribute) == target.role,
              try string(target.element, kAXIdentifierAttribute) == target.identifier else { throw AXContentFailure.identity }
        if let value = target.value, try identityValue(target.element) != value { throw AXContentFailure.identity }
        if let text = target.text, try textValue(target.element, range: text.range) != text.text {
            throw AXContentFailure.identity
        }
        // AX and WindowServer can publish a move at different instants. Wait
        // under a protective cover rather than permanently losing a valid target.
        guard try matchesWindow(target.element, window: window, primaryTop: primaryTop) else { return .pending }
        let area: CGRect
        if let text = target.text {
            area = try rangeBounds(target.element, range: text.range, primaryTop: primaryTop)
        } else { area = try bounds(target.element, primaryTop: primaryTop) }
        var viewport = window.frame
        var ancestor = try elementAttribute(target.element, kAXParentAttribute)
        var reachedWindow = false
        for _ in 0..<24 {
            guard let current = ancestor else { break }
            let role = try string(current, kAXRoleAttribute)
            if role == kAXWindowRole {
                guard CFEqual(current, target.ownerElement) else { throw AXContentFailure.identity }
                reachedWindow = true
                break
            }
            if role == kAXScrollAreaRole {
                viewport = viewport.intersection(try bounds(current, primaryTop: primaryTop))
            }
            ancestor = try elementAttribute(current, kAXParentAttribute)
        }
        guard reachedWindow else { throw AXContentFailure.identity }
        guard let visible = OverlayGeometry.clipped(area, to: viewport) else { return .offscreen }
        return .visible(DesktopContentGeometry(area: area, viewport: visible, windowFrame: window.frame))
    }

    private static let mutableRoles: Set<String> = [kAXTextFieldRole, kAXComboBoxRole, kAXButtonRole,
        kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXSliderRole]

    private static func sourceStillMatches(_ context: DesktopContentContext) -> Bool {
        let records = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        guard let record = records.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == context.window.identity.windowID
                && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == context.window.identity.processID
        }), let bounds = record[kCGWindowBounds as String] as? [String: Any],
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        return DesktopWindowScope.appKitFrame(frame, primaryTop: context.primaryTop) == context.window.frame
    }

    private func textIdentity(_ element: AXUIElement, rectangle: CGRect, primaryTop: CGFloat) throws -> TextIdentity? {
        guard let names = try parameterNames(element), names.contains(kAXRangeForPositionParameterizedAttribute),
              names.contains(kAXBoundsForRangeParameterizedAttribute), names.contains(kAXStringForRangeParameterizedAttribute) else { return nil }
        let firstPoint = CGPoint(x: rectangle.minX + 1, y: primaryTop - rectangle.maxY + 1)
        let lastPoint = CGPoint(x: rectangle.maxX - 1, y: primaryTop - rectangle.minY - 1)
        let first = try rangeAt(element, point: firstPoint)
        let last = try rangeAt(element, point: lastPoint)
        guard first.location >= 0, last.location >= 0, first.length >= 0, last.length >= 0,
              first.location < Int.max - first.length, last.location < Int.max - last.length else { return nil }
        let lower = min(first.location, last.location)
        let upper = max(first.location + first.length, last.location + last.length)
        guard upper > lower, upper - lower <= 65_536 else { return nil }
        let range = CFRange(location: lower, length: upper - lower)
        let text = try textValue(element, range: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        _ = try rangeBounds(element, range: range, primaryTop: primaryTop)
        return TextIdentity(range: range, text: text)
    }

    private func matchesWindow(_ element: AXUIElement, window: DesktopWindow, primaryTop: CGFloat) throws -> Bool {
        try checkBudget()
        guard try access.processID(of: element) == window.identity.processID,
              let owner = try elementAttribute(element, kAXWindowAttribute) else { return false }
        let frame = try bounds(owner, primaryTop: primaryTop)
        return abs(frame.minX - window.frame.minX) <= 4 && abs(frame.minY - window.frame.minY) <= 4
            && abs(frame.width - window.frame.width) <= 4 && abs(frame.height - window.frame.height) <= 4
    }

    private func identityValue(_ element: AXUIElement) throws -> String? {
        // An AX identifier alone is insufficient for a recycled row or image.
        let values = try [string(element, kAXValueAttribute), string(element, kAXTitleAttribute),
                          string(element, kAXDescriptionAttribute)].compactMap { $0 }
        let token = values.joined(separator: "\u{1f}").trimmingCharacters(in: .whitespacesAndNewlines)
        return token.count >= 3 && token.utf16.count <= 65_536 ? token : nil
    }

    private func checkBudget() throws {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw AXContentFailure.budget }
    }

    private func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        try checkBudget()
        return try access.attribute(element, name)
    }

    private func string(_ element: AXUIElement, _ name: String) throws -> String? {
        try attribute(element, name) as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) throws -> AXUIElement? {
        guard let value = try attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func bounds(_ element: AXUIElement, primaryTop: CGFloat) throws -> CGRect {
        guard let position = try attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = try attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { throw AXContentFailure.unavailable }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite else { throw AXContentFailure.unavailable }
        return DesktopWindowScope.appKitFrame(CGRect(origin: point, size: dimensions), primaryTop: primaryTop)
    }

    private func parameterNames(_ element: AXUIElement) throws -> [String]? {
        try checkBudget()
        return try access.parameterNames(element)
    }

    private func parameter(_ element: AXUIElement, _ name: String, value: CFTypeRef) throws -> CFTypeRef {
        try checkBudget()
        return try access.parameter(element, name, value: value)
    }

    private func rangeAt(_ element: AXUIElement, point: CGPoint) throws -> CFRange {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { throw AXContentFailure.unavailable }
        let result = try parameter(element, kAXRangeForPositionParameterizedAttribute, value: value)
        var range = CFRange()
        guard CFGetTypeID(result) == AXValueGetTypeID(), AXValueGetValue(result as! AXValue, .cfRange, &range) else { throw AXContentFailure.unavailable }
        return range
    }

    private func textValue(_ element: AXUIElement, range: CFRange) throws -> String {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range),
              let text = try parameter(element, kAXStringForRangeParameterizedAttribute, value: value) as? String else { throw AXContentFailure.unavailable }
        return text
    }

    private func rangeBounds(_ element: AXUIElement, range: CFRange, primaryTop: CGFloat) throws -> CGRect {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { throw AXContentFailure.unavailable }
        let result = try parameter(element, kAXBoundsForRangeParameterizedAttribute, value: value)
        var rect = CGRect.zero
        guard CFGetTypeID(result) == AXValueGetTypeID(), AXValueGetValue(result as! AXValue, .cgRect, &rect),
              rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { throw AXContentFailure.unavailable }
        return DesktopWindowScope.appKitFrame(rect, primaryTop: primaryTop)
    }
}
