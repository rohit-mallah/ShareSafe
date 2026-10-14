import AppKit
import ScreenCaptureKit

/// One Add action selects one source. Repeat Add to create independent streams.
/// This adapter never enumerates all SCShareableContent or requests broad TCC
/// access. Existing streams survive a canceled or rejected selection.
@MainActor
final class SystemCapturePicker {
    var onSelection: ((CaptureSource) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((String) -> Void)?

    private var observer: SystemCapturePickerObserver?
    private var requestID: UUID?
    private var canceled = false

    func present() {
        guard #available(macOS 15.2, *) else {
            onError?("Safe system window selection requires macOS 15.2 or later so ShareSafe can monitor the selected window. Use Advanced source list and allow Screen Recording on this Mac.")
            return
        }
        // The OS callbacks identify a stream, not a presentation. Keep a single
        // pending presentation so an old dialog cannot satisfy a newer request.
        guard observer == nil else {
            if canceled { onError?("Close the current system picker, then choose Add again.") }
            return
        }
        let id = UUID()
        let relay = SystemCapturePickerObserver(owner: self, requestID: id)
        observer = relay
        requestID = id
        canceled = false

        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.allowsChangingSelectedContent = false
        configuration.excludedBundleIDs = Bundle.main.bundleIdentifier.map { [$0] } ?? []
        // Core Graphics window metadata is available without Screen Recording.
        // These valid IDs also exclude this process when developing unbundled.
        let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        configuration.excludedWindowIDs = windowInfo.compactMap { item in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                == ProcessInfo.processInfo.processIdentifier,
                  let number = item[kCGWindowNumber as String] as? NSNumber else { return nil }
            return number.intValue
        }

        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = nil
        picker.add(relay)
        picker.isActive = true
        picker.present()
    }

    /// Discard this Add action without touching any capture stream. There is no
    /// public picker-dismiss API. Leave its relay until the OS closes the dialog
    /// so a late completion cannot be mistaken for a subsequent Add action.
    func cancel() {
        guard requestID != nil, !canceled else { return }
        canceled = true
        onCancel?()
    }

    /// Stop accepting this pending selection. Stream shutdown belongs to the
    /// caller; disabling the singleton here could affect other selected sources.
    func stop() {
        cancel()
    }

    @available(macOS 14.0, *)
    fileprivate func selected(_ filter: SCContentFilter, stream: SCStream?, request: UUID) {
        guard stream == nil, request == requestID else { return }
        let shouldDeliver = !canceled
        finishRequest()
        guard shouldDeliver else { return }
        do {
            onSelection?(try CaptureSource.pickerSelection(filter: filter))
        } catch {
            onError?(error.localizedDescription)
        }
    }

    @available(macOS 14.0, *)
    fileprivate func didCancel(stream: SCStream?, request: UUID) {
        guard stream == nil, request == requestID else { return }
        let shouldDeliver = !canceled
        finishRequest()
        if shouldDeliver { onCancel?() }
    }

    @available(macOS 14.0, *)
    fileprivate func failed(_ error: Error, request: UUID) {
        guard request == requestID else { return }
        let shouldDeliver = !canceled
        finishRequest()
        if shouldDeliver {
            onError?("The system picker could not open. Try Add again, or use Advanced source list. \(error.localizedDescription)")
        }
    }

    @available(macOS 14.0, *)
    private func finishRequest() {
        if let observer { SCContentSharingPicker.shared.remove(observer) }
        observer = nil
        requestID = nil
        canceled = false
        // Keep the system integration active for the already-authorized streams.
    }
}

/// A separate relay per presentation guards callbacks already queued when the
/// request completes. SCK does not promise observer delivery on the UI actor.
@MainActor
private final class SystemCapturePickerObserver: NSObject {
    weak var owner: SystemCapturePicker?
    let requestID: UUID

    init(owner: SystemCapturePicker, requestID: UUID) {
        self.owner = owner
        self.requestID = requestID
    }
}

@available(macOS 14.0, *)
extension SystemCapturePickerObserver: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker,
                                          didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.owner?.didCancel(stream: stream, request: self.requestID)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker,
                                          didUpdateWith filter: SCContentFilter,
                                          for stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.owner?.selected(filter, stream: stream, request: self.requestID)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.owner?.failed(error, request: self.requestID)
        }
    }
}
