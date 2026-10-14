import CoreGraphics

/// Geometry in AppKit's global, bottom-left-origin screen coordinates (points).
/// Display origins may be negative or vertically offset; never assume a main-display origin.
public enum OverlayGeometry {
    public static func selection(
        start: CGPoint, end: CGPoint, in screen: CGRect, minimumSize: CGFloat = 3
    ) -> CGRect? {
        guard valid(screen), finite(start), finite(end), minimumSize.isFinite,
              minimumSize > 0,
              start.x >= screen.minX, start.x <= screen.maxX,
              start.y >= screen.minY, start.y <= screen.maxY else { return nil }
        let endpoint = CGPoint(
            x: min(max(end.x, screen.minX), screen.maxX),
            y: min(max(end.y, screen.minY), screen.maxY)
        )
        let rectangle = CGRect(
            x: min(start.x, endpoint.x), y: min(start.y, endpoint.y),
            width: abs(endpoint.x - start.x), height: abs(endpoint.y - start.y)
        )
        guard rectangle.width >= minimumSize, rectangle.height >= minimumSize else { return nil }
        return rectangle
    }

    public static func clipped(_ rectangle: CGRect, to screen: CGRect) -> CGRect? {
        guard valid(screen), valid(rectangle) else { return nil }
        let result = rectangle.intersection(screen)
        return valid(result) ? result : nil
    }

    /// Keeps a moved cover on its owning display. Oversized covers are clipped to fit.
    public static func moved(_ rectangle: CGRect, by delta: CGVector, in screen: CGRect) -> CGRect? {
        guard valid(rectangle), valid(screen), delta.dx.isFinite, delta.dy.isFinite else { return nil }
        let width = min(rectangle.width, screen.width)
        let height = min(rectangle.height, screen.height)
        let x = rectangle.minX + delta.dx
        let y = rectangle.minY + delta.dy
        guard x.isFinite, y.isFinite else { return nil }
        return CGRect(
            x: min(max(x, screen.minX), screen.maxX - width),
            y: min(max(y, screen.minY), screen.maxY - height),
            width: width, height: height
        )
    }

    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }

    private static func valid(_ rectangle: CGRect) -> Bool {
        finite(rectangle.origin) && rectangle.size.width.isFinite && rectangle.size.height.isFinite
            && rectangle.maxX.isFinite && rectangle.maxY.isFinite
            && rectangle.size.width > 0 && rectangle.size.height > 0
    }
}
