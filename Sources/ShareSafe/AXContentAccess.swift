import ApplicationServices
import Foundation

enum AXContentFailure: Error { case unavailable, identity, budget }

/// Primitive AX calls are isolated here so reader identity/range/clipping policy
/// can be tested without granting a test runner access to the user's apps.
protocol AXContentAccess: Sendable {
    var isTrusted: Bool { get }
    func hitTest(processID: pid_t, point: CGPoint) throws -> AXUIElement?
    func processID(of element: AXUIElement) throws -> pid_t
    func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef?
    func parameterNames(_ element: AXUIElement) throws -> [String]?
    func parameter(_ element: AXUIElement, _ name: String, value: CFTypeRef) throws -> CFTypeRef
}

struct SystemAXContentAccess: AXContentAccess {
    var isTrusted: Bool { AXIsProcessTrusted() }
    init() {
        // The system-wide object sets this client's default. A timeout on an
        // application object alone does not propagate to returned child objects.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.025)
    }
    func hitTest(processID: pid_t, point: CGPoint) throws -> AXUIElement? {
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.025)
        var element: AXUIElement?
        try Self.check(AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element))
        return element
    }
    func processID(of element: AXUIElement) throws -> pid_t {
        var pid: pid_t = 0
        try Self.check(AXUIElementGetPid(element, &pid))
        return pid
    }
    func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.025)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return nil }
        try Self.check(error)
        return value
    }
    func parameterNames(_ element: AXUIElement) throws -> [String]? {
        AXUIElementSetMessagingTimeout(element, 0.025)
        var names: CFArray?
        let error = AXUIElementCopyParameterizedAttributeNames(element, &names)
        if error == .notImplemented || error == .attributeUnsupported { return nil }
        try Self.check(error)
        return names as? [String]
    }
    func parameter(_ element: AXUIElement, _ name: String, value: CFTypeRef) throws -> CFTypeRef {
        AXUIElementSetMessagingTimeout(element, 0.025)
        var result: CFTypeRef?
        try Self.check(AXUIElementCopyParameterizedAttributeValue(element, name as CFString, value, &result))
        guard let result else { throw AXContentFailure.unavailable }
        return result
    }
    static func check(_ error: AXError) throws {
        // AXStringForRange reports illegalArgument when an edit invalidates
        // a retained range. That is lost identity, even during a window move.
        if error == .invalidUIElement || error == .apiDisabled || error == .illegalArgument {
            throw AXContentFailure.identity
        }
        guard error == .success else { throw AXContentFailure.unavailable }
    }
}
