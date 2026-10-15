import CoreGraphics
import Foundation
import ShareSafeCore

struct DesktopWindowIdentity: Equatable, Sendable {
    let windowID: UInt32
    let processID: Int32
}

struct DesktopWindow: Equatable, Sendable {
    let identity: DesktopWindowIdentity
    let frame: CGRect
    let layer: Int
}

/// Points measured from the source window's top-left corner. Moving a window
/// preserves the area; resizing never pretends to track or rescale its content.
struct DesktopWindowAnchor: Equatable {
    let identity: DesktopWindowIdentity
    private let offset: CGPoint
    private let size: CGSize

    init?(window: DesktopWindow, rectangle: CGRect) {
        guard let clipped = OverlayGeometry.clipped(rectangle, to: window.frame) else { return nil }
        identity = window.identity
        offset = CGPoint(x: clipped.minX - window.frame.minX, y: window.frame.maxY - clipped.maxY)
        size = clipped.size
    }

    func rectangle(in windowFrame: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX + offset.x, y: windowFrame.maxY - offset.y - size.height,
               width: size.width, height: size.height)
    }
}

/// A front-to-back WindowServer snapshot. No screen pixels, window titles,
/// Accessibility APIs, or privacy authorization requests are used.
struct DesktopWindowScope {
    let windows: [DesktopWindow]

    func window(for identity: DesktopWindowIdentity) -> DesktopWindow? {
        windows.first { $0.identity == identity }
    }

    func target(at point: CGPoint) -> DesktopWindow? {
        // Do not select through a menu/popover onto an unrelated window below.
        guard let first = windows.first(where: { $0.frame.contains(point) }), first.layer == 0 else { return nil }
        return first
    }

    func visibleFragments(for anchor: DesktopWindowAnchor) -> [CGRect] {
        guard let index = windows.firstIndex(where: { $0.identity == anchor.identity }),
              let frame = OverlayGeometry.clipped(anchor.rectangle(in: windows[index].frame),
                                                   to: windows[index].frame) else { return [] }
        // Native overlays sit above other apps. Cut away everything in front
        // of the source so an overlay cannot blur a covering app or sibling window.
        return windows[..<index].reduce([frame]) { fragments, occluder in
            fragments.flatMap { Self.subtract(occluder.frame, from: $0) }
        }
    }

    private static func subtract(_ obstruction: CGRect, from frame: CGRect) -> [CGRect] {
        guard let intersection = OverlayGeometry.clipped(obstruction, to: frame) else { return [frame] }
        return [
            CGRect(x: frame.minX, y: frame.minY, width: intersection.minX - frame.minX, height: frame.height),
            CGRect(x: intersection.maxX, y: frame.minY, width: frame.maxX - intersection.maxX, height: frame.height),
            CGRect(x: intersection.minX, y: frame.minY, width: intersection.width, height: intersection.minY - frame.minY),
            CGRect(x: intersection.minX, y: intersection.maxY, width: intersection.width, height: frame.maxY - intersection.maxY)
        ].filter { $0.width > 0 && $0.height > 0 }
    }

    static func appKitFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    static func read(primaryTop: CGFloat, excludingProcessID ownProcessID: Int32) -> DesktopWindowScope {
        let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = records.compactMap { record -> DesktopWindow? in
            guard let number = record[kCGWindowNumber as String] as? NSNumber,
                  let owner = record[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value != ownProcessID,
                  let layer = record[kCGWindowLayer as String] as? NSNumber, layer.intValue >= 0,
                  let bounds = record[kCGWindowBounds as String] as? [String: Any],
                  let cgFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  OverlayGeometry.clipped(cgFrame, to: cgFrame) != nil else { return nil }
            return DesktopWindow(identity: .init(windowID: number.uint32Value, processID: owner.int32Value),
                                 frame: appKitFrame(cgFrame, primaryTop: primaryTop), layer: layer.intValue)
        }
        return DesktopWindowScope(windows: windows)
    }
}
