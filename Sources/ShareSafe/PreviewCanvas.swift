import AppKit
import SwiftUI
import ShareSafeCore

struct PreviewCanvas: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> MaskCanvas { let view = MaskCanvas(); view.model = model; return view }
    func updateNSView(_ view: MaskCanvas, context: Context) { view.model = model; view.needsDisplay = true }
}

final class MaskCanvas: NSView {
    weak var model: AppModel?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var gestureSource: String?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var contentRect: CGRect {
        guard let frame = model?.originalFrame else { return .zero }
        return PreviewGeometry.aspectFit(source: CGSize(width: frame.width, height: frame.height), in: bounds.insetBy(dx: 12, dy: 12))
    }
    override func resetCursorRects() {
        if model?.drawMode == true || model?.choosingCrop == true { addCursorRect(bounds, cursor: .crosshair) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.055, green: 0.067, blue: 0.082, alpha: 1).setFill()
        NSBezierPath(rect: bounds).fill()
        guard let model, let frame = model.originalFrame else { return }
        let rect = contentRect
        NSImage(cgImage: frame, size: CGSize(width: frame.width, height: frame.height))
            .draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        for (index, mask) in model.masks.enumerated() {
            drawMask(mask.rect.rect(in: rect), label: "\(index+1) · \(mask.style.label)", draft: false)
        }
        if let startPoint, let currentPoint, let mask = NormalizedRect.fromDrag(start: startPoint, end: currentPoint, in: rect) {
            drawMask(mask.rect(in: rect), label: model.choosingCrop ? "Release to crop" : "Release to hide", draft: true)
        }
    }
    private func drawMask(_ rect: CGRect, label: String, draft: Bool) {
        let accent = NSColor(calibratedRed: 0.40, green: 0.88, blue: 0.72, alpha: 1)
        accent.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)); border.lineWidth = 1.5
        if draft { border.setLineDash([5, 3], count: 2, phase: 0) }; border.stroke()
        guard rect.width > 70 && rect.height > 24 else { return }
        (label as NSString).draw(at: CGPoint(x: rect.minX+3, y: max(0, rect.minY-16)), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: accent])
    }
    override func mouseDown(with event: NSEvent) {
        guard let model, (model.drawMode || model.choosingCrop), model.originalFrame != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard contentRect.contains(point) else { return }
        window?.makeFirstResponder(self)
        startPoint = point; currentPoint = point; gestureSource = model.selectedID
        if !model.choosingCrop { model.beginMask() }; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let rect = gestureSource == model?.selectedID ? NormalizedRect.fromDrag(start: startPoint, end: convert(event.locationInWindow, from: nil), in: contentRect) : nil
        self.startPoint = nil; currentPoint = nil; gestureSource = nil
        if model?.choosingCrop == true { model?.finishCrop(rect) } else { model?.finishMask(rect) }; needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && (startPoint != nil || model?.choosingCrop == true) {
            startPoint = nil; currentPoint = nil; gestureSource = nil
            if model?.choosingCrop == true { model?.finishCrop(nil) } else { model?.finishMask(nil) }; needsDisplay = true
        } else { super.keyDown(with: event) }
    }
}
