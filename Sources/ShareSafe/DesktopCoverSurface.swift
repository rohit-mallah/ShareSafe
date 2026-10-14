import AppKit
import ShareSafeCore

/// WindowServer supplies the backdrop effect. This view never reads or copies
/// another application's pixels and does not need Screen Recording permission.
@MainActor
final class DesktopCoverSurface: NSView {
    let style: MaskStyle
    let backdrop = NSVisualEffectView()
    private let outline = NSView()
    var reduceTransparency: Bool { didSet { updateAppearance() } }
    var editing = false {
        didSet {
            outline.isHidden = !editing
            updateSelectionOutline()
            window?.invalidateCursorRects(for: self)
        }
    }
    var selected = false { didSet { updateSelectionOutline() } }
    var onSelect: (() -> Void)?
    var onSelectNext: ((Bool) -> Void)?
    var onNudge: ((CGVector) -> Void)?
    var coverFrame: (() -> CGRect?)?
    var onMove: ((CGRect, CGVector) -> Void)?
    var onRemove: (() -> Void)?
    var onCancel: (() -> Void)?
    private var dragStart: CGPoint?
    private var initialFrame: CGRect?

    var usesSolidCover: Bool { style == .solid || reduceTransparency }
    override var isOpaque: Bool { usesSolidCover }
    override var acceptsFirstResponder: Bool { editing }
    override var needsPanelToBecomeKey: Bool { editing }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { editing }

    init(frame: CGRect, style: MaskStyle, reduceTransparency: Bool) {
        self.style = style
        self.reduceTransparency = reduceTransparency
        super.init(frame: frame)
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        backdrop.setAccessibilityElement(false)
        addSubview(backdrop)
        outline.frame = bounds
        outline.autoresizingMask = [.width, .height]
        outline.wantsLayer = true
        outline.layer?.borderColor = NSColor.systemMint.cgColor
        outline.layer?.borderWidth = 3
        outline.isHidden = true
        outline.setAccessibilityElement(false)
        addSubview(outline)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    private func updateAppearance() {
        backdrop.isHidden = usesSolidCover
        window?.isOpaque = usesSolidCover
        window?.backgroundColor = usesSolidCover ? .black : .clear
        needsDisplay = true
    }

    private func updateSelectionOutline() {
        outline.layer?.borderColor = (selected ? NSColor.systemMint : NSColor.white.withAlphaComponent(0.5)).cgColor
        outline.layer?.borderWidth = selected ? 3 : 1
    }

    override func keyDown(with event: NSEvent) {
        if !handleEditKey(event) { super.keyDown(with: event) }
    }

    /// Only the focused editing surface handles ordinary movement/delete keys.
    /// Global shortcuts are routed separately; modified app shortcuts pass through.
    @discardableResult
    func handleEditKey(_ event: NSEvent) -> Bool {
        guard editing, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: onNudge?(CGVector(dx: -step, dy: 0))
        case 124: onNudge?(CGVector(dx: step, dy: 0))
        case 125: onNudge?(CGVector(dx: 0, dy: -step))
        case 126: onNudge?(CGVector(dx: 0, dy: step))
        case 51, 117: onRemove?()
        case 48: onSelectNext?(event.modifierFlags.contains(.shift))
        case 53: onCancel?()
        default: return false
        }
        return true
    }

    // The material subview must not swallow drag/right-click events in edit mode.
    override func hitTest(_ point: NSPoint) -> NSView? {
        editing && bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        if usesSolidCover {
            NSColor.black.setFill()
            bounds.fill()
        }
    }

    override func resetCursorRects() {
        if editing { addCursorRect(bounds, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard editing, let window else { return }
        onSelect?()
        window.makeKey()
        window.makeFirstResponder(self)
        dragStart = window.convertPoint(toScreen: event.locationInWindow)
        initialFrame = coverFrame?() ?? window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard editing, let dragStart, let initialFrame, let window else { return }
        let position = window.convertPoint(toScreen: event.locationInWindow)
        onMove?(initialFrame, CGVector(dx: position.x - dragStart.x, dy: position.y - dragStart.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        initialFrame = nil
    }

    override func rightMouseDown(with event: NSEvent) { if editing { onRemove?() } }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
