import AppKit
import ShareSafeCore

/// Presenter-only hints, never protection. The chosen capture must exclude these
/// ShareSafe-owned windows independently of NSWindow.sharingType.
@MainActor
final class PresenterOutlineController {
    private var panels: [String: NSPanel] = [:]
    private var task: Task<Void, Never>?

    func start(workspace: ProtectedWorkspaceModel) {
        task?.cancel()
        task = Task { @MainActor [weak self, weak workspace] in
            while !Task.isCancelled {
                guard let self, let workspace else { return }
                self.update(sources: workspace.sources)
                do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            }
        }
    }

    func update(sources: [ProtectedSource]) {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { clear(); return }
        let visibleWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let frontWindow = visibleWindows.first {
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }?[kCGWindowNumber as String] as? NSNumber
        var desired: [String: CGRect] = [:]
        for source in sources {
            guard let capture = source.captureSource, capture.presenterOutlineSafe,
                  let bounds = capture.presenterBounds, source.model.originalFrame != nil,
                  source.model.presenterOutlineGeometryKnown,
                  !source.model.choosingCrop else { continue }
            if capture.kind == .window, capture.id != frontWindow.map({ "window:\($0.uint32Value)" }) { continue }
            let crop = source.model.crop
            for mask in source.model.masks {
                let region = NormalizedRect(x: crop.x + mask.rect.x * crop.width,
                    y: crop.y + mask.rect.y * crop.height,
                    width: mask.rect.width * crop.width, height: mask.rect.height * crop.height)
                let cg = region.rect(in: bounds)
                desired["\(source.id):\(mask.id)"] = CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
            }
        }
        for key in Array(panels.keys) where desired[key] == nil { panels.removeValue(forKey: key)?.close() }
        for (key, rect) in desired {
            let panel: NSPanel
            if let existing = panels[key] {
                panel = existing
            } else {
                panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                panel.title = "ShareSafe — presenter outline"
                panel.contentView = OutlineSurface()
                panels[key] = panel
            }
            if panel.frame != rect { panel.setFrame(rect, display: true) }
            panel.orderFrontRegardless()
        }
    }

    func stop() { task?.cancel(); task = nil; clear() }
    private func clear() { panels.values.forEach { $0.close() }; panels.removeAll() }
}

private final class OutlineSurface: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.40, green: 0.88, blue: 0.72, alpha: 1).setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.stroke()
    }
}
