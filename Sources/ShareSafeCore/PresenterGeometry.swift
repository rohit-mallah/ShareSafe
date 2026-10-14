import CoreGraphics

public enum PresenterGeometry {
    /// Original-screen outlines are safe only when source coordinates map to the
    /// whole capture buffer. Resized windows can be letterboxed by ScreenCaptureKit.
    public static func contentFillsBuffer(_ rect: CGRect, scale: Double, width: Int, height: Int) -> Bool {
        guard scale.isFinite, scale > 0, width > 0, height > 0,
              rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return false }
        let tolerance = 1.5
        return abs(rect.minX * scale) < tolerance && abs(rect.minY * scale) < tolerance
            && abs(rect.width * scale - Double(width)) < tolerance
            && abs(rect.height * scale - Double(height)) < tolerance
    }
}
