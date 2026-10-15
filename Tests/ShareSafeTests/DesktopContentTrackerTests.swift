import Foundation
import Testing
@testable import ShareSafe

/// A delayed provider models AX IPC without requiring a real privacy grant.
private actor DelayedContentReader: DesktopContentReading {
    private var captureWaiter: CheckedContinuation<DesktopContentState, Never>?
    private var refreshWaiter: CheckedContinuation<[(UUID, DesktopContentState)], Never>?
    private(set) var captures = 0
    private(set) var refreshes = 0
    private(set) var removed: [UUID] = []

    func capture(id: UUID, rectangle: CGRect, window: DesktopWindow, primaryTop: CGFloat) async -> DesktopContentState {
        captures += 1
        return await withCheckedContinuation { captureWaiter = $0 }
    }
    func refresh(_ contexts: [DesktopContentContext]) async -> [(UUID, DesktopContentState)] {
        refreshes += 1
        return await withCheckedContinuation { refreshWaiter = $0 }
    }
    func remove(_ id: UUID) { removed.append(id) }
    func finishCapture(_ state: DesktopContentState) { captureWaiter?.resume(returning: state); captureWaiter = nil }
    func finishRefresh(_ results: [(UUID, DesktopContentState)]) { refreshWaiter?.resume(returning: results); refreshWaiter = nil }
}

@MainActor
struct DesktopContentTrackerTests {
    private var window: DesktopWindow {
        .init(identity: .init(windowID: 10, processID: 100), frame: CGRect(x: 0, y: 0, width: 500, height: 400), layer: 0)
    }
    private var geometry: DesktopContentGeometry {
        .init(area: CGRect(x: 40, y: 60, width: 100, height: 30),
              viewport: window.frame, windowFrame: window.frame)
    }
    private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Background provider did not reach the expected state")
    }

    @Test func existingGrantIsReusedAndMissingAccessIsRequestedOnlyOnce() {
        var trusted = true
        var requests = 0
        let tracker = DesktopContentTracker(reader: DelayedContentReader(), readTrust: { trusted }, requestAccess: { requests += 1 })
        tracker.requestAccessIfNeeded()
        #expect(requests == 0)
        trusted = false
        #expect(!tracker.isTrusted && requests == 0)
        tracker.requestAccessIfNeeded()
        tracker.requestAccessIfNeeded()
        #expect(requests == 1)
    }

    @Test func slowCaptureDoesNotBlockUIOrRaceAnEarlyRefresh() async throws {
        let reader = DelayedContentReader()
        let tracker = DesktopContentTracker(reader: reader, now: { 10 })
        let id = tracker.capture(rectangle: geometry.area, window: window, primaryTop: 400)
        try await eventually { await reader.captures == 1 }
        tracker.refresh([.init(id: id, window: window, primaryTop: 400)])
        #expect(tracker.state(for: id) == .pending)
        #expect(await reader.refreshes == 0)
        var mainActorResponsive = false
        Task { @MainActor in mainActorResponsive = true }
        try await eventually { mainActorResponsive }
        await reader.finishCapture(.visible(geometry))
        try await eventually { tracker.state(for: id) == .visible(geometry) }
        tracker.remove(id)
    }

    @Test func removingDuringCaptureCannotResurrectTheTarget() async throws {
        let reader = DelayedContentReader()
        let tracker = DesktopContentTracker(reader: reader)
        let id = tracker.capture(rectangle: geometry.area, window: window, primaryTop: 400)
        try await eventually { await reader.captures == 1 }
        tracker.remove(id)
        await reader.finishCapture(.visible(geometry))
        try await eventually { await reader.removed.filter { $0 == id }.count >= 2 }
        #expect(tracker.state(for: id) == .lost)
    }

    @Test func delayedRefreshExpiresGeometryAndCannotResurrectARemovedTarget() async throws {
        let reader = DelayedContentReader()
        var clock: TimeInterval = 10
        let tracker = DesktopContentTracker(reader: reader, now: { clock })
        let id = tracker.capture(rectangle: geometry.area, window: window, primaryTop: 400)
        try await eventually { await reader.captures == 1 }
        await reader.finishCapture(.visible(geometry))
        try await eventually { tracker.state(for: id) == .visible(geometry) }
        let contexts = [DesktopContentContext(id: id, window: window, primaryTop: 400)]
        tracker.refresh(contexts)
        try await eventually { await reader.refreshes == 1 }
        tracker.refresh(contexts)
        #expect(await reader.refreshes == 1)
        clock += 0.36
        #expect(tracker.state(for: id) == .pending)
        tracker.remove(id)
        await reader.finishRefresh([(id, .visible(geometry))])
        try await eventually { await reader.removed.contains(id) }
        // Allow the main-actor completion to consume the response.
        await Task.yield()
        #expect(tracker.state(for: id) == .lost)
    }

    @Test func lateResponsesCannotMakeOldGeometryLookFresh() async throws {
        let reader = DelayedContentReader()
        var clock: TimeInterval = 10
        var notifications = 0
        let tracker = DesktopContentTracker(reader: reader, now: { clock })
        tracker.onChange = { notifications += 1 }
        let id = tracker.capture(rectangle: geometry.area, window: window, primaryTop: 400)
        try await eventually { await reader.captures == 1 }
        clock += 1
        await reader.finishCapture(.visible(geometry))
        try await eventually { notifications == 1 }
        #expect(tracker.state(for: id) == .pending)
        tracker.refresh([.init(id: id, window: window, primaryTop: 400)])
        try await eventually { await reader.refreshes == 1 }
        clock += 1
        await reader.finishRefresh([(id, .visible(geometry))])
        try await eventually { notifications == 2 }
        #expect(tracker.state(for: id) == .pending)
        tracker.remove(id)
    }

    @Test func oldOffscreenResultsAlsoExpireInsteadOfHidingAReappearingTarget() async throws {
        let reader = DelayedContentReader()
        var clock: TimeInterval = 10
        let tracker = DesktopContentTracker(reader: reader, now: { clock })
        let id = tracker.capture(rectangle: geometry.area, window: window, primaryTop: 400)
        try await eventually { await reader.captures == 1 }
        await reader.finishCapture(.offscreen)
        try await eventually { tracker.state(for: id) == .offscreen }
        clock += 1
        #expect(tracker.state(for: id) == .pending)
        tracker.remove(id)
    }
}
