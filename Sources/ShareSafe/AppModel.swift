import AppKit
import Combine
import ShareSafeCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sources: [CaptureSource] = []
    @Published var search = ""
    @Published private(set) var selectedID: String?
    @Published private(set) var sourceTitle = "Choose what to share"
    @Published private(set) var originalFrame: CGImage?
    @Published private(set) var audienceFrame: CGImage? { didSet { onOutputChanged?() } }
    @Published private(set) var masks: [MaskRegion] = []
    @Published private(set) var outputEnabled = false
    @Published private(set) var isLoading = false
    @Published private(set) var isCapturing = false
    @Published private(set) var message = "Start with a window, a display, or the built-in demo."
    @Published private(set) var errorMessage: String?
    @Published var maskStyle: MaskStyle = .blur
    @Published var drawMode = true
    @Published private(set) var isDrawing = false
    @Published var showHelp = false
    @Published private(set) var crop = MirrorGeometry.full
    @Published private(set) var choosingCrop = false
    @Published private(set) var fullOutputBlur = false
    @Published var presetName = ""
    @Published private(set) var savedRegions: [SavedMirrorRegion] = []
    private var fullFrame: CGImage?
    private let presetsKey = "ShareSafe.mirrorRegions.v1"
    var showAudience: (() -> Void)?
    // Synchronous invalidation prevents an old composite surviving a privacy edit.
    var onPrivacyChange: (() -> Void)?
    var onOutputChanged: (() -> Void)?

    private let capture = CaptureEngine()
    private let renderer = PrivacyRenderer()
    private var token = UUID()
    private var geometry: CaptureGeometry?
    private var wasLiveBeforeDrawing = false
    private var shouldInvalidateMasksAfterDrawing = false
    private var task: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let regions = try? JSONDecoder().decode([SavedMirrorRegion].self, from: data) { savedRegions = regions }

        capture.onFrame = { [weak self] image, geometry, token in
            self?.accept(image, geometry: geometry, token: token)
        }
        capture.onError = { [weak self] message, token in
            guard let self, token == self.token else { return }
            self.panicBlank()
            self.originalFrame = nil
            self.isCapturing = false
            self.errorMessage = message
            self.message = "Capture stopped. Choose the source again to reconnect."
        }
    }

    var filteredSources: [CaptureSource] {
        guard !search.isEmpty else { return sources }
        return sources.filter { ($0.title + " " + $0.subtitle).localizedCaseInsensitiveContains(search) }
    }
    var canGoLive: Bool { originalFrame != nil && !isLoading && !isDrawing && !choosingCrop && errorMessage == nil }
    var outputLabel: String {
        isDrawing ? "Protected while drawing" : outputEnabled ? "Output live" : "Audience paused"
    }

    func refreshSources() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                sources = try await capture.listSources()
                errorMessage = nil
                message = sources.isEmpty ? "No windows found. Open an app and refresh." : "Choose a source. Your audience stays paused until you go live."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func select(_ source: CaptureSource) {
        beginSource(id: source.id, title: source.title)
        let nextToken = token
        task = Task {
            do {
                try await capture.start(source: source, token: nextToken)
                guard token == nextToken, !Task.isCancelled else { return }
                isLoading = false
                isCapturing = true
                message = "Review the preview and masks, then choose Go live."
            } catch {
                guard token == nextToken else { return }
                isLoading = false
                errorMessage = error.localizedDescription
                message = "Capture needs your attention."
            }
        }
    }

    func selectDemo() {
        beginSource(id: "demo", title: "Demo workspace")
        let nextToken = token
        task = Task {
            await capture.stop()
            guard token == nextToken, !Task.isCancelled else { return }
            fullFrame = DemoFrame.make()
            updatePreview()
            isLoading = false
            isCapturing = false
            message = "Demo only. Drag over an email or amount to test a privacy mask."
        }
    }

    private func beginSource(id: String, title: String) {
        onPrivacyChange?()
        if isDrawing { shouldInvalidateMasksAfterDrawing = true }
        task?.cancel()
        token = UUID()
        panicBlank()
        selectedID = id
        sourceTitle = title
        originalFrame = nil
        fullFrame = nil
        crop = MirrorGeometry.full
        choosingCrop = false
        fullOutputBlur = false
        geometry = nil
        masks = []
        isLoading = true
        isCapturing = false
        errorMessage = nil
        message = "Preparing source. Audience output is paused."
    }

    private func accept(_ image: CGImage, geometry next: CaptureGeometry, token frameToken: UUID) {
        guard token == frameToken else { return }
        if let previous = geometry, previous != next {
            onPrivacyChange?()
            panicBlank()
            masks.removeAll()
            crop = MirrorGeometry.full
            choosingCrop = false
            if isDrawing { shouldInvalidateMasksAfterDrawing = true }
            message = "Source size changed. Check mask positions, then Go live again."
        }
        geometry = next
        fullFrame = image
        updatePreview()
        // Starting SCStream can deliver a frame before start() returns.
        if outputEnabled && !isDrawing { renderOutput() }
    }

    func goLive() {
        guard canGoLive else { return }
        outputEnabled = true
        renderOutput()
        if outputEnabled {
            message = "Share only “ShareSafe Protected View — Share this window” in your meeting."
            showAudience?()
        }
    }

    func panicBlank() {
        outputEnabled = false
        audienceFrame = nil
        wasLiveBeforeDrawing = false
    }

    func toggleOutput() { outputEnabled ? panicBlank() : goLive() }

    func beginMask() {
        guard originalFrame != nil else { return }
        onPrivacyChange?()
        wasLiveBeforeDrawing = outputEnabled
        isDrawing = true
        shouldInvalidateMasksAfterDrawing = false
        audienceFrame = nil
    }

    func finishMask(_ rect: NormalizedRect?) {
        defer { wasLiveBeforeDrawing = false; shouldInvalidateMasksAfterDrawing = false }
        isDrawing = false
        if let rect, !shouldInvalidateMasksAfterDrawing {
            masks.append(MaskRegion(rect: rect, style: maskStyle))
        }
        if wasLiveBeforeDrawing && outputEnabled && !shouldInvalidateMasksAfterDrawing { renderOutput() }
    }

    func removeMask(_ id: UUID) {
        onPrivacyChange?()
        panicBlank()
        masks.removeAll { $0.id == id }
        if outputEnabled && !isDrawing { renderOutput() }
    }

    func clearMasks() {
        onPrivacyChange?()
        panicBlank()
        masks.removeAll()
        message = "Masks cleared. Review the preview before going live again."
    }

    func cancelEditing() {
        if isDrawing { finishMask(nil) }
        if choosingCrop { finishCrop(nil) }
    }

    func protectedPreview() -> CGImage? {
        guard let originalFrame, !isDrawing, !choosingCrop else { return nil }
        return renderer.render(originalFrame, masks: fullOutputBlur
            ? masks + [MaskRegion(rect: MirrorGeometry.full, style: .blur)] : masks)
    }

    private func renderOutput() {
        guard outputEnabled, !isDrawing, let originalFrame else { audienceFrame = nil; return }
        guard let processed = renderer.render(originalFrame, masks: fullOutputBlur ? masks + [MaskRegion(rect: MirrorGeometry.full, style: .blur)] : masks) else {
            panicBlank()
            errorMessage = "Could not render the protected output. Re-select the source to retry."
            return
        }
        audienceFrame = processed
    }

    var canCrop: Bool { selectedID?.hasPrefix("display:") == true || selectedID == "demo" }

    var presenterOutlineGeometryKnown: Bool {
        guard let geometry, let fullFrame else { return false }
        return PresenterGeometry.contentFillsBuffer(geometry.contentRect, scale: geometry.scaleFactor,
            width: fullFrame.width, height: fullFrame.height)
    }

    private func updatePreview() {
        guard let fullFrame else { originalFrame = nil; return }
        originalFrame = choosingCrop ? fullFrame : MirrorGeometry.crop(fullFrame, to: crop)
    }

    func beginCrop() {
        guard canCrop, fullFrame != nil, !isDrawing else { return }
        onPrivacyChange?()
        panicBlank()
        choosingCrop = true
        updatePreview()
        message = "Drag the region to share. Escape keeps the previous region."
    }

    func finishCrop(_ region: NormalizedRect?) {
        guard choosingCrop else { return }
        choosingCrop = false
        if let region { setCrop(region) }
        updatePreview()
    }

    func setCrop(_ region: NormalizedRect) {
        guard canCrop, let fullFrame,
              MirrorGeometry.pixelCrop(region, width: fullFrame.width, height: fullFrame.height) != nil else { return }
        onPrivacyChange?()
        panicBlank()
        if isDrawing { shouldInvalidateMasksAfterDrawing = true }
        crop = region
        masks.removeAll()
        updatePreview()
        message = "Region changed. Add privacy masks and review before Go live."
    }

    func toggleFullBlur() {
        if fullOutputBlur {
            onPrivacyChange?()
            panicBlank()
        }
        fullOutputBlur.toggle()
        if outputEnabled && !isDrawing { renderOutput() }
    }

    func saveRegion() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = selectedID, id.hasPrefix("display:"), let geometry, !name.isEmpty else { return }
        savedRegions.append(SavedMirrorRegion(name: String(name.prefix(80)), sourceID: id,
            sourceWidth: geometry.sourceWidth, sourceHeight: geometry.sourceHeight, crop: crop))
        presetName = ""
        savePresets()
    }

    func restoreRegion(_ region: SavedMirrorRegion) {
        panicBlank()
        guard let id = selectedID, let geometry,
              region.matches(sourceID: id, width: geometry.sourceWidth, height: geometry.sourceHeight) else {
            message = "Select the saved display at its original size first, then restore this region."
            return
        }
        choosingCrop = false
        setCrop(region.crop)
    }

    func deleteRegion(_ id: UUID) {
        savedRegions.removeAll { $0.id == id }
        savePresets()
    }

    private func savePresets() {
        if let data = try? JSONEncoder().encode(savedRegions) { UserDefaults.standard.set(data, forKey: presetsKey) }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func stop() {
        onPrivacyChange?()
        task?.cancel()
        token = UUID()
        panicBlank()
        originalFrame = nil
        fullFrame = nil
        choosingCrop = false
        isDrawing = false
        isCapturing = false
        isLoading = false
        Task { await capture.stop() }
        message = "Capture stopped. Pick a source to start again."
    }
}
