import CoreGraphics
import Foundation

/// Accepts processed source images only. Missing inputs must be handled by the
/// caller as a paused session, never replaced with their unprocessed originals.
public final class ProtectedCompositor {
    public init() {}

    public func render(_ processedFrames: [CGImage], width: Int = 1920, height: Int = 1080) -> CGImage? {
        guard !processedFrames.isEmpty, width > 0, height > 0,
              width <= 8192, height <= 8192,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        context.setFillColor(red: 0.035, green: 0.045, blue: 0.055, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let columns = Int(ceil(sqrt(Double(processedFrames.count))))
        let rows = Int(ceil(Double(processedFrames.count) / Double(columns)))
        let cellWidth = CGFloat(width) / CGFloat(columns)
        let cellHeight = CGFloat(height) / CGFloat(rows)
        context.interpolationQuality = .high
        for (index, image) in processedFrames.enumerated() {
            let cell = CGRect(x: CGFloat(index % columns) * cellWidth,
                y: CGFloat(rows - 1 - index / columns) * cellHeight,
                width: cellWidth, height: cellHeight)
            let target = PreviewGeometry.aspectFit(source: CGSize(width: image.width, height: image.height), in: cell)
            context.draw(image, in: target)
        }
        return context.makeImage()
    }
}
