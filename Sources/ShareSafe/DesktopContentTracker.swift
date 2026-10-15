import Foundation
import CoreGraphics

struct DesktopContentGeometry: Equatable, Sendable {
    let area: CGRect
    let viewport: CGRect
    let windowFrame: CGRect
}

enum DesktopContentState: Equatable, Sendable {
    case pending
    case visible(DesktopContentGeometry)
    case offscreen
    case lost
    case unsupported
}

struct DesktopContentContext: Sendable {
    let id: UUID
    let window: DesktopWindow
    let primaryTop: CGFloat
}

protocol DesktopContentReading: Actor {
    func capture(id: UUID, rectangle: CGRect, window: DesktopWindow, primaryTop: CGFloat) async -> DesktopContentState
    func refresh(_ contexts: [DesktopContentContext]) async -> [(UUID, DesktopContentState)]
    func remove(_ id: UUID) async
}

@MainActor
protocol DesktopContentTracking: AnyObject {
    var isTrusted: Bool { get }
    var onChange: (() -> Void)? { get set }
    func requestAccessIfNeeded()
    func capture(rectangle: CGRect, window: DesktopWindow, primaryTop: CGFloat) -> UUID
    func state(for id: UUID) -> DesktopContentState
    func refresh(_ contexts: [DesktopContentContext])
    func remove(_ id: UUID)
}

/// AX communication lives on a serial background actor. The main thread only reads
/// cached geometry; a slow or stopped source app cannot block emergency controls.
@MainActor
final class DesktopContentTracker: DesktopContentTracking {
    var onChange: (() -> Void)?
    var isTrusted: Bool { readTrust() }
    private let reader: any DesktopContentReading
    private let readTrust: () -> Bool
    private let requestAccess: () -> Void
    private let now: () -> TimeInterval
    private var requestedAccess = false
    private var updating = false
    private var entries: [UUID: Entry] = [:]

    private struct Entry {
        var state: DesktopContentState = .pending
        var bound = false
        var updatedAt: TimeInterval
    }

    init(reader: any DesktopContentReading = AXContentReader(),
         readTrust: @escaping () -> Bool = { AXContentReader.isTrusted },
         requestAccess: @escaping () -> Void = { AXContentReader.requestAccess() },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.reader = reader
        self.readTrust = readTrust
        self.requestAccess = requestAccess
        self.now = now
    }

    func requestAccessIfNeeded() {
        guard !isTrusted, !requestedAccess else { return }
        requestedAccess = true
        requestAccess()
    }

    func capture(rectangle: CGRect, window: DesktopWindow, primaryTop: CGFloat) -> UUID {
        let id = UUID()
        let requestedAt = now()
        entries[id] = Entry(updatedAt: requestedAt)
        Task { [reader, weak self] in
            let state = await reader.capture(id: id, rectangle: rectangle, window: window, primaryTop: primaryTop)
            guard let self, self.entries[id] != nil else {
                await reader.remove(id)
                return
            }
            self.entries[id] = Entry(state: state, bound: true, updatedAt: requestedAt)
            self.onChange?()
        }
        return id
    }

    func state(for id: UUID) -> DesktopContentState {
        guard let entry = entries[id] else { return .lost }
        switch entry.state {
        case .visible, .offscreen:
            // Old positions must not masquerade as current content geometry.
            return now() - entry.updatedAt > 0.35 ? .pending : entry.state
        default: return entry.state
        }
    }

    func refresh(_ contexts: [DesktopContentContext]) {
        guard !updating, !contexts.isEmpty else { return }
        let active = contexts.filter { entries[$0.id]?.bound == true }
        guard !active.isEmpty else { return }
        updating = true
        let requestedAt = now()
        Task { [reader, weak self] in
            let results = await reader.refresh(active)
            guard let self else { return }
            self.updating = false
            for (id, state) in results where self.entries[id] != nil {
                self.entries[id] = Entry(state: state, bound: true, updatedAt: requestedAt)
            }
            self.onChange?()
        }
    }

    func remove(_ id: UUID) {
        entries.removeValue(forKey: id)
        Task { [reader] in await reader.remove(id) }
    }
}
