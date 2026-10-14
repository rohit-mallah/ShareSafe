import AppKit
import Combine
import ShareSafeCore

enum ProtectedLayout: String, CaseIterable {
    case focused = "Selected source"
    case grid = "All sources"
}

@MainActor
final class ProtectedSource: Identifiable {
    let id = UUID()
    var captureSource: CaptureSource?
    let model = AppModel()
    var title: String
    var subscription: AnyCancellable?

    init(source: CaptureSource) {
        captureSource = source
        title = source.title
    }

    init(demoNumber: Int) {
        captureSource = nil
        title = "Demo workspace \(demoNumber)"
    }
}

@MainActor
final class ProtectedWorkspaceModel: ObservableObject {
    @Published private(set) var sources: [ProtectedSource] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var outputEnabled = false
    @Published private(set) var audienceFrame: CGImage?
    @Published private(set) var layout: ProtectedLayout = .focused
    @Published private(set) var fullOutputBlur = false
    @Published private(set) var message = "Add a window or screen, mark private areas, then share the protected view."
    @Published private(set) var errorMessage: String?
    @Published private(set) var legacySources: [CaptureSource] = []
    @Published private(set) var isLoadingSources = false
    @Published var showLegacySources = false
    @Published var showHelp = false
    var showAudience: (() -> Void)?
    var requestSharing: (() -> Void)?
    var onOutlinesChanged: (() -> Void)?

    private let picker = SystemCapturePicker()
    private let enumeration = CaptureEngine()
    private let compositor = ProtectedCompositor()
    private let renderer = PrivacyRenderer()
    private var demoCount = 0
    private var isStarting = false
    private var stopped = false
    private var enumerationTask: Task<Void, Never>?

    init() {
        picker.onSelection = { [weak self] source in self?.add(source) }
        picker.onError = { [weak self] error in self?.errorMessage = error }
        picker.onCancel = { [weak self] in
            self?.message = "Selection cancelled. Your added sources and masks are unchanged."
        }
    }

    var selected: ProtectedSource? { sources.first { $0.id == selectedID } }
    var canGoLive: Bool { !sources.isEmpty && sources.allSatisfy { $0.model.canGoLive } }
    var maskCount: Int { sources.reduce(0) { $0 + $1.model.masks.count } }

    func chooseSource() {
        guard !stopped else { return }
        pause()
        selected?.model.cancelEditing()
        errorMessage = nil
        picker.present()
    }

    func add(_ source: CaptureSource) {
        guard !stopped else { return }
        if let existing = sources.first(where: { $0.captureSource?.id == source.id }) {
            select(existing.id)
            if existing.model.errorMessage != nil || (!existing.model.isLoading && existing.model.originalFrame == nil) {
                pause()
                existing.captureSource = source
                existing.title = source.title
                existing.model.select(source)
                message = "Source reconnected. Add masks again and review before resuming."
            } else {
                message = "That source is already added. Its masks are unchanged."
            }
            showLegacySources = false
            return
        }
        let item = ProtectedSource(source: source)
        install(item)
        item.model.select(source)
        showLegacySources = false
    }

    @discardableResult
    func addDemo() -> ProtectedSource {
        demoCount += 1
        let item = ProtectedSource(demoNumber: demoCount)
        guard !stopped else { return item }
        install(item)
        item.model.selectDemo()
        return item
    }

    private func install(_ source: ProtectedSource) {
        pause()
        selected?.model.cancelEditing()
        source.model.onPrivacyChange = { [weak self, weak source] in
            guard let self, let source, self.sources.contains(where: { $0 === source }) else { return }
            self.pause()
            self.message = "Source or privacy settings changed. Review, then start protected output again."
        }
        source.model.onOutputChanged = { [weak self, weak source] in
            guard let self, let source, self.sources.contains(where: { $0 === source }),
                  self.outputEnabled, !self.isStarting else { return }
            self.updateAudience()
        }
        source.subscription = source.model.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
                self?.onOutlinesChanged?()
            }
        }
        sources.append(source)
        selectedID = source.id
        errorMessage = nil
        message = "Mark private areas on each source. Originals stay clear and usable."
        onOutlinesChanged?()
    }

    func select(_ id: UUID) {
        guard selectedID != id, sources.contains(where: { $0.id == id }) else { return }
        pause()
        selected?.model.cancelEditing()
        selectedID = id
        message = "Masks retained. Review the selected source, then resume the protected output."
        onOutlinesChanged?()
    }

    func remove(_ id: UUID) {
        pause()
        guard let source = sources.first(where: { $0.id == id }) else { return }
        source.model.onPrivacyChange = nil
        source.model.onOutputChanged = nil
        source.subscription?.cancel()
        source.model.stop()
        sources.removeAll { $0.id == id }
        if selectedID == id { selectedID = sources.first?.id }
        message = "Source removed. Review the remaining sources before resuming."
        onOutlinesChanged?()
    }

    func setLayout(_ next: ProtectedLayout) {
        guard layout != next else { return }
        pause()
        layout = next
        message = "Layout changed. Review the audience preview before resuming."
    }

    func goLive() {
        guard !stopped, canGoLive else { return }
        isStarting = true
        for source in sources { source.model.goLive() }
        isStarting = false
        guard sources.allSatisfy({ $0.model.outputEnabled && $0.model.audienceFrame != nil }) else {
            pause()
            errorMessage = "A source could not produce protected pixels. Output stays paused."
            return
        }
        outputEnabled = true
        updateAudience()
        if outputEnabled {
            message = "In your meeting, share “ShareSafe Protected View — Share this window”."
            showAudience?()
        }
    }

    func pause() {
        outputEnabled = false
        audienceFrame = nil
        for source in sources { source.model.panicBlank() }
    }

    func toggleOutput() { outputEnabled ? pause() : goLive() }

    func toggleFullBlur() {
        if fullOutputBlur { pause() }
        fullOutputBlur.toggle()
        if outputEnabled { updateAudience() }
        if !fullOutputBlur { message = "Full-view blur removed. Review, then resume protected output." }
    }

    func protectedPreview() -> CGImage? {
        guard let selected else { return nil }
        let visible = layout == .grid ? sources : [selected]
        let frames = visible.compactMap { $0.model.protectedPreview() }
        guard frames.count == visible.count, let composite = compositor.render(frames) else { return nil }
        return fullOutputBlur
            ? renderer.render(composite, masks: [MaskRegion(rect: MirrorGeometry.full, style: .blur)]) : composite
    }

    private func updateAudience() {
        guard outputEnabled else { audienceFrame = nil; return }
        // All streams must remain healthy, even when only one is displayed.
        guard sources.allSatisfy({ $0.model.outputEnabled && $0.model.audienceFrame != nil }),
              let selected else {
            pause()
            message = "A source paused or became unavailable. Review it before resuming."
            return
        }
        let visible = layout == .grid ? sources : [selected]
        let processed = visible.compactMap { $0.model.audienceFrame }
        guard processed.count == visible.count, let composite = compositor.render(processed),
              let output = fullOutputBlur
                ? renderer.render(composite, masks: [MaskRegion(rect: MirrorGeometry.full, style: .blur)])
                : composite else {
            pause()
            errorMessage = "Protected output could not be rendered. Nothing unprocessed was shown."
            return
        }
        audienceFrame = output
    }

    func loadLegacySources(displaysOnly: Bool = false) {
        guard !isLoadingSources, !stopped else { return }
        pause()
        selected?.model.cancelEditing()
        errorMessage = nil
        isLoadingSources = true
        enumerationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingSources = false }
            do {
                let next = try await self.enumeration.listSources()
                guard !Task.isCancelled, !self.stopped else { return }
                self.legacySources = displaysOnly ? next.filter { $0.kind == .display } : next
                self.showLegacySources = true
            } catch {
                guard !Task.isCancelled, !self.stopped else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        stopped = true
        picker.stop()
        enumerationTask?.cancel()
        pause()
        for source in sources {
            source.model.onPrivacyChange = nil
            source.model.onOutputChanged = nil
            source.subscription?.cancel()
            source.model.stop()
        }
        sources = []
        selectedID = nil
        onOutlinesChanged?()
    }
}
