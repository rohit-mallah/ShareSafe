import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

enum CaptureSourceKind: Equatable {
    case window
    case display
}

struct CaptureSource: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: CaptureSourceKind
    fileprivate let window: SCWindow?
    fileprivate let display: SCDisplay?
    // A picker filter is itself the session grant. Retain that exact object rather
    // than rebuilding it from a broadly enumerated list of shareable content.
    fileprivate let authorizedFilter: SCContentFilter?
    fileprivate let authorizedSize: CGSize?
    fileprivate let authorizedScale: CGFloat?

    init(id: String, title: String, subtitle: String, kind: CaptureSourceKind,
         window: SCWindow?, display: SCDisplay?, authorizedFilter: SCContentFilter? = nil,
         authorizedSize: CGSize? = nil, authorizedScale: CGFloat? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.window = window
        self.display = display
        self.authorizedFilter = authorizedFilter
        self.authorizedSize = authorizedSize
        self.authorizedScale = authorizedScale
    }

    /// Global Core Graphics coordinates (origin at the top of the primary display).
    /// Query window metadata again so moving the original moves its outline too.
    var presenterBounds: CGRect? {
        if let window {
            guard let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.windowID)
                as? [[String: Any]], let current = info.first,
                (current[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == window.owningApplication?.processID,
                (current[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                let dictionary = current[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                Self.valid(bounds) else { return nil }
            return bounds
        }
        if let display {
            guard CGDisplayIsActive(display.displayID) != 0 else { return nil }
            let bounds = CGDisplayBounds(display.displayID)
            return Self.valid(bounds) ? bounds : nil
        }
        return nil
    }

    /// Window filters omit other applications' overlay windows; legacy display
    /// filters exclude the whole ShareSafe application. Unknown picker metadata
    /// has no trustworthy original-screen location and must not get an outline.
    var presenterOutlineSafe: Bool {
        presenterBounds != nil && (window != nil || (display != nil && authorizedFilter == nil))
    }

    @available(macOS 14.0, *)
    static func pickerSelection(filter: SCContentFilter) throws -> CaptureSource {
        // Picker excludedBundleIDs/excludedWindowIDs prevent *selection* of the
        // app; they are not documented exclusions from a full-display stream.
        // Reconstructing a display filter may discard its session authorization.
        // Require the explicit legacy permission flow rather than capture even
        // one frame containing our unredacted private preview.
        guard filter.style != .display else { throw CaptureEngineError.unsafePickerDisplay }
        guard filter.style == .window else { throw CaptureEngineError.unsupportedPickerSelection }
        let size = filter.contentRect.size
        let scale = CGFloat(filter.pointPixelScale)
        guard Self.valid(filter.contentRect), scale.isFinite, scale > 0 else {
            throw CaptureEngineError.invalidPickerGeometry
        }

        guard #available(macOS 15.2, *), filter.includedWindows.count == 1 else {
            // Source identity is required for independent loss monitoring.
            throw CaptureEngineError.unidentifiedPickerWindow
        }
        let selectedWindow = filter.includedWindows[0]
        guard let owner = selectedWindow.owningApplication,
              owner.processID != ProcessInfo.processInfo.processIdentifier,
              Bundle.main.bundleIdentifier.map({ owner.bundleIdentifier != $0 }) ?? true else {
            throw CaptureEngineError.ownWindowSelected
        }
        let appName = owner.applicationName
        let title = selectedWindow.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CaptureSource(id: "window:\(selectedWindow.windowID)",
                             title: title.isEmpty ? appName : title,
                             subtitle: "\(appName) · System selection", kind: .window,
                             window: selectedWindow, display: nil, authorizedFilter: filter,
                             authorizedSize: size, authorizedScale: scale)
    }

    private static func valid(_ bounds: CGRect) -> Bool {
        bounds.minX.isFinite && bounds.minY.isFinite
            && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width > 0 && bounds.height > 0
    }

    static func == (lhs: CaptureSource, rhs: CaptureSource) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
            && lhs.kind == rhs.kind
    }
}

/// Source geometry, rather than just the dimensions of the fixed-size output buffer.
/// SCK describes contentRect in surface points and contentScale as the factor from
/// original content to surface content. Retaining both catches proportional resizes
/// that would otherwise leave the encoded image dimensions unchanged.
struct CaptureGeometry: Equatable {
    let sourceWidth: Double
    let sourceHeight: Double
    let scaleFactor: Double
    let contentScale: Double
    let contentRect: CGRect
    let outputWidth: Int
    let outputHeight: Int
    let screenWidth: Double?
    let screenHeight: Double?

    fileprivate init?(attachments: [SCStreamFrameInfo: Any], outputWidth: Int, outputHeight: Int) {
        guard let rect = Self.rectangle(attachments[.contentRect]),
              let scale = attachments[.contentScale] as? NSNumber,
              let factor = attachments[.scaleFactor] as? NSNumber else { return nil }
        let contentScale = scale.doubleValue
        let scaleFactor = factor.doubleValue
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0,
              contentScale.isFinite, contentScale > 0,
              scaleFactor.isFinite, scaleFactor > 0 else { return nil }

        // Sub-millipoint rounding removes metadata floating-point jitter without
        // hiding a one-pixel source change. Raw scaling is retained to six decimals.
        func rounded(_ value: Double, precision: Double = 1_000) -> Double {
            (value * precision).rounded() / precision
        }
        self.sourceWidth = rounded(rect.width / contentScale)
        self.sourceHeight = rounded(rect.height / contentScale)
        self.scaleFactor = rounded(scaleFactor, precision: 1_000_000)
        self.contentScale = rounded(contentScale, precision: 1_000_000)
        self.contentRect = CGRect(x: rounded(rect.minX), y: rounded(rect.minY),
                                  width: rounded(rect.width), height: rounded(rect.height))
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        if #available(macOS 13.1, *),
           let screenRect = Self.rectangle(attachments[.screenRect]),
           screenRect.width.isFinite, screenRect.height.isFinite,
           screenRect.width > 0, screenRect.height > 0 {
            // Position is deliberately omitted: moving a window is not resizing it.
            screenWidth = rounded(screenRect.width)
            screenHeight = rounded(screenRect.height)
        } else {
            screenWidth = nil
            screenHeight = nil
        }
    }

    private static func rectangle(_ value: Any?) -> CGRect? {
        if let rect = value as? CGRect { return rect }
        if let value = value as? NSValue { return value.rectValue }
        if let dictionary = value as? NSDictionary {
            return CGRect(dictionaryRepresentation: dictionary)
        }
        return nil
    }
}

private enum CaptureEngineError: LocalizedError {
    case permissionOrEnumeration(String)
    case missingSource
    case cannotExcludeSelf
    case unsafePickerDisplay
    case unsupportedPickerSelection
    case invalidPickerGeometry
    case ownWindowSelected
    case unidentifiedPickerWindow
    case pickerStartFailed(String)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionOrEnumeration(let detail):
            return "Unable to list capture sources. Allow ShareSafe in System Settings → Privacy & Security → Screen Recording (Screen & System Audio Recording on newer macOS), then quit and reopen ShareSafe if macOS asks. \(detail)"
        case .missingSource:
            return "The selected window or display is no longer available. Refresh the source list and select it again."
        case .cannotExcludeSelf:
            return "ShareSafe could not identify its own application for exclusion from display capture. Select a single window, or refresh and try again."
        case .unsafePickerDisplay:
            return "To share a display safely, use Advanced source list and allow Screen Recording. Window selection uses session consent."
        case .unsupportedPickerSelection:
            return "Select one window or one display per Add action. Add another source to protect more content."
        case .invalidPickerGeometry:
            return "The selected window's size is unavailable. Select the window again to continue safely."
        case .ownWindowSelected:
            return "Select an original window from another app. ShareSafe's private preview and protected output cannot be capture sources."
        case .unidentifiedPickerWindow:
            return "ShareSafe could not identify exactly one selected window for source-loss monitoring. Try Add window again, or use Advanced source list."
        case .pickerStartFailed(let detail):
            return "Capture could not start from the system selection. Select the window again. \(detail)"
        case .startFailed(let detail):
            return "Capture could not start. Check Screen Recording permission, refresh the source list, and try again. \(detail)"
        }
    }
}

@MainActor
final class CaptureEngine {
    var onFrame: ((CGImage, CaptureGeometry, UUID) -> Void)?
    var onError: ((String, UUID) -> Void)?

    private var activeStream: SCStream?
    private var activeSink: CaptureStreamSink?
    private var activeAvailabilityTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var lifecycleBusy = false
    private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []
    // SCStreamConfiguration.backgroundColor is an unsafe, non-retaining property.
    private static let captureBackgroundColor = CGColor(gray: 0, alpha: 1)

    /// Call from a user action. ScreenCaptureKit supplies the native permission prompt.
    func listSources() async throws -> [CaptureSource] {
        let content = try await shareableContent()
        let windows = content.windows.compactMap { window -> CaptureSource? in
            guard let application = window.owningApplication,
                  !isOwnApplication(application), window.isOnScreen,
                  window.windowLayer == 0,
                  window.frame.width >= 80, window.frame.height >= 60 else { return nil }
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let appName = application.applicationName
            return CaptureSource(id: "window:\(window.windowID)",
                                 title: title.isEmpty ? "\(appName) window" : title,
                                 subtitle: appName, kind: .window,
                                 window: window, display: nil)
        }.sorted {
            let appOrder = $0.subtitle.localizedCaseInsensitiveCompare($1.subtitle)
            return appOrder == .orderedSame
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : appOrder == .orderedAscending
        }
        let displays = content.displays.sorted { $0.displayID < $1.displayID }.enumerated().map { index, display in
            CaptureSource(id: "display:\(display.displayID)", title: "Display \(index + 1)",
                          subtitle: "\(display.width) × \(display.height) points · ShareSafe excluded",
                          kind: .display, window: nil, display: display)
        }
        return windows + displays
    }

    func start(source: CaptureSource, token: UUID) async throws {
        generation &+= 1
        let requestedGeneration = generation
        activeSink?.invalidate()
        await acquireLifecycle()
        defer { releaseLifecycle() }
        try ensureCurrent(requestedGeneration)
        await stopActiveStream()
        try ensureCurrent(requestedGeneration)

        let filter: SCContentFilter
        let size: CGSize
        let backingScale: CGFloat
        if let authorizedFilter = source.authorizedFilter {
            guard let authorizedSize = source.authorizedSize,
                  let authorizedScale = source.authorizedScale,
                  authorizedSize.width.isFinite, authorizedSize.width > 0,
                  authorizedSize.height.isFinite, authorizedSize.height > 0,
                  authorizedScale.isFinite, authorizedScale > 0 else {
                throw CaptureEngineError.invalidPickerGeometry
            }
            // No SCShareableContent enumeration on the native picker path. The
            // OS-supplied filter is the only scope we were authorized to capture.
            filter = authorizedFilter
            size = authorizedSize
            backingScale = authorizedScale
        } else {
            // Legacy mode is deliberately user initiated and may request broad
            // Screen Recording permission. Refresh its stale backing objects.
            let content = try await shareableContent()
            try ensureCurrent(requestedGeneration)
            switch source.kind {
            case .window:
                guard let id = source.window?.windowID,
                      let window = content.windows.first(where: { $0.windowID == id }),
                      let owner = window.owningApplication, !isOwnApplication(owner),
                      owner.processID == source.window?.owningApplication?.processID,
                      window.frame.width > 0, window.frame.height > 0 else {
                    throw CaptureEngineError.missingSource
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
                size = window.frame.size
                backingScale = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor ?? 2
            case .display:
                guard let id = source.display?.displayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw CaptureEngineError.missingSource
                }
                let ownApplications = content.applications.filter(isOwnApplication)
                // Failing closed here also avoids recursive preview capture.
                guard !ownApplications.isEmpty else { throw CaptureEngineError.cannotExcludeSelf }
                filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
                size = CGSize(width: display.width, height: display.height)
                backingScale = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
                })?.backingScaleFactor ?? 1
            }
        }

        let configuration = SCStreamConfiguration()
        let pixelWidth = max(1, size.width * backingScale)
        let pixelHeight = max(1, size.height * backingScale)
        let fit = min(1, 1920 / pixelWidth, 1080 / pixelHeight)
        configuration.width = max(1, Int((pixelWidth * fit).rounded(.down)))
        configuration.height = max(1, Int((pixelHeight * fit).rounded(.down)))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.scalesToFit = true
        configuration.capturesAudio = false
        configuration.excludesCurrentProcessAudio = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.backgroundColor = Self.captureBackgroundColor
        if #available(macOS 14.0, *) {
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = true
        }
        if #available(macOS 14.2, *) {
            // Privacy masks are reviewed against the selected original window,
            // not an implicitly enlarged composition containing child windows.
            configuration.includeChildWindows = false
        }
        if #available(macOS 15.0, *) { configuration.captureMicrophone = false }

        let sink = CaptureStreamSink(token: token, onFrame: { [weak self] image, geometry, token in
            guard let self, self.generation == requestedGeneration else { return }
            self.onFrame?(image, geometry, token)
        }, onError: { [weak self] message, token in
            guard let self, self.generation == requestedGeneration else { return }
            self.activeSink?.invalidate()
            self.activeAvailabilityTask?.cancel()
            self.activeAvailabilityTask = nil
            self.onError?(message, token)
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestedGeneration else { return }
                await self.stop()
            }
        })
        let stream = SCStream(filter: filter, configuration: configuration, delegate: sink)
        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            activeStream = stream
            activeSink = sink
            try await stream.startCapture()
            try ensureCurrent(requestedGeneration)
            monitorAvailability(source: source, sink: sink)
        } catch {
            sink.invalidate()
            if activeStream === stream { await stopActiveStream() }
            if error is CancellationError { throw error }
            if source.authorizedFilter != nil {
                throw CaptureEngineError.pickerStartFailed(error.localizedDescription)
            }
            throw CaptureEngineError.startFailed(error.localizedDescription)
        }
    }

    func stop() async {
        generation &+= 1
        // Invalidate before awaiting, so already-queued frames cannot reach clients.
        activeSink?.invalidate()
        await acquireLifecycle()
        defer { releaseLifecycle() }
        await stopActiveStream()
    }

    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw CaptureEngineError.permissionOrEnumeration(error.localizedDescription)
        }
    }

    private func isOwnApplication(_ application: SCRunningApplication) -> Bool {
        application.processID == ProcessInfo.processInfo.processIdentifier
            || (Bundle.main.bundleIdentifier.map { application.bundleIdentifier == $0 } ?? false)
    }

    private func ensureCurrent(_ requestedGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard requestedGeneration == generation else { throw CancellationError() }
    }

    private func stopActiveStream() async {
        let stream = activeStream
        let sink = activeSink
        activeAvailabilityTask?.cancel()
        activeAvailabilityTask = nil
        sink?.invalidate()
        activeStream = nil
        activeSink = nil
        if let stream {
            // An already stopped stream can legitimately reject stopCapture.
            try? await stream.stopCapture()
            if let sink { try? stream.removeStreamOutput(sink, type: .screen) }
        }
    }

    private func monitorAvailability(source: CaptureSource, sink: CaptureStreamSink) {
        let windowID = source.window?.windowID
        let windowOwnerID = source.window?.owningApplication?.processID
        let displayID = source.display?.displayID
        // Some macOS releases send only idle frames for a minimized window. An
        // independent visibility check prevents retaining its previous frame forever.
        // This uses window metadata, not another capture or TCC permission request.
        activeAvailabilityTask = Task { @MainActor [weak sink] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return }
                guard let sink, sink.isValid else { return }
                if let windowID {
                    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                        as? [[String: Any]]
                    guard let window = info?.first,
                          (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == windowOwnerID,
                          (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true else {
                        sink.fail("The captured window is minimized, closed, or no longer on screen. Show it, then select it again.")
                        return
                    }
                } else if let displayID, CGDisplayIsActive(displayID) == 0 {
                    sink.fail("The captured display is no longer active. Refresh the source list and select a display again.")
                    return
                }
            }
        }
    }

    // Actor isolation alone does not serialize across awaits. This FIFO gate makes
    // stop/start completion explicit, while generation invalidation stays immediate.
    private func acquireLifecycle() async {
        if !lifecycleBusy {
            lifecycleBusy = true
            return
        }
        await withCheckedContinuation { lifecycleWaiters.append($0) }
    }

    private func releaseLifecycle() {
        if lifecycleWaiters.isEmpty {
            lifecycleBusy = false
        } else {
            lifecycleWaiters.removeFirst().resume()
        }
    }
}

/// One sink per stream: its immutable token can never become the token of a newer
/// stream. Core Image rendering happens on a serial capture queue, not the UI actor.
private final class CaptureStreamSink: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "ShareSafe.capture.frames", qos: .userInitiated)
    private let token: UUID
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @MainActor (CGImage, CaptureGeometry, UUID) -> Void
    private let onError: @MainActor (String, UUID) -> Void
    private let lock = NSLock()
    private var valid = true

    init(token: UUID,
         onFrame: @escaping @MainActor (CGImage, CaptureGeometry, UUID) -> Void,
         onError: @escaping @MainActor (String, UUID) -> Void) {
        self.token = token
        self.onFrame = onFrame
        self.onError = onError
    }

    func invalidate() {
        lock.lock()
        valid = false
        lock.unlock()
    }

    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isValid, type == .screen else { return }
        guard sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let frame = attachments.first,
              let rawStatus = frame[.status] as? NSNumber,
              let status = SCFrameStatus(rawValue: rawStatus.intValue) else {
            fail("Capture returned an invalid frame. Select the source again to resume.")
            return
        }

        switch status {
        case .complete:
            break
        case .stopped:
            fail("The capture stream stopped. Select the source again to resume.")
            return
        case .blank, .suspended:
            fail("The capture source became unavailable or was suspended. Select it again when it is visible.")
            return
        default:
            return
        }

        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            fail("Capture returned an empty frame. Select the source again to resume.")
            return
        }
        guard let geometry = CaptureGeometry(attachments: frame,
                                             outputWidth: CVPixelBufferGetWidth(pixelBuffer),
                                             outputHeight: CVPixelBufferGetHeight(pixelBuffer)) else {
            fail("Capture geometry is unavailable. Capture was paused to prevent masks from using an unknown source size.")
            return
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let rendered = context.createCGImage(image, from: image.extent) else {
            fail("The captured frame could not be rendered. Select the source again to resume.")
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.isValid else { return }
            self.onFrame(rendered, geometry, self.token)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fail("Capture stopped: \(error.localizedDescription). Check the source and Screen Recording permission, then select it again.")
    }

    @available(macOS 15.2, *)
    func streamDidBecomeInactive(_ stream: SCStream) {
        fail("The captured window closed or became unavailable. Refresh the source list and select a window again.")
    }

    func fail(_ message: String) {
        lock.lock()
        let shouldReport = valid
        valid = false
        lock.unlock()
        guard shouldReport else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onError(message, self.token)
        }
    }
}
