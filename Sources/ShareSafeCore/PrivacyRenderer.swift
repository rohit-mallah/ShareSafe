import CoreGraphics
import CoreImage
import Foundation

/// Burns masks into new image pixels. A rendering failure returns nil; callers must blank output.
public final class PrivacyRenderer {
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let imageContext: CIContext

    public init() {
        imageContext = CIContext(options: [.cacheIntermediates: false])
    }

    public func render(_ image: CGImage, masks: [MaskRegion]) -> CGImage? {
        guard let context = bitmapContext(width: image.width, height: image.height) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setBlendMode(.copy)
        context.draw(image, in: bounds)

        let blurMasks = masks.filter { $0.style == .blur }
        if !blurMasks.isEmpty {
            let input = CIImage(cgImage: image)
            let blurred = input.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24.0])
            for mask in blurMasks {
                let area = pixelRect(mask.rect, in: bounds)
                guard !area.isEmpty else { continue }
                guard let pixels = imageContext.createCGImage(
                    blurred.cropped(to: area), from: area, format: .RGBA8, colorSpace: colorSpace
                ) else { return nil }
                context.draw(pixels, in: area)
            }
        }

        // Solid coverage is authoritative even when a later blur overlaps it.
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        for mask in masks where mask.style == .solid {
            let area = pixelRect(mask.rect, in: bounds)
            guard !area.isEmpty else { continue }
            context.fill(area)
        }
        return context.makeImage()
    }

    public func blank(width: Int = 1920, height: Int = 1080) -> CGImage? {
        guard let context = bitmapContext(width: width, height: height) else { return nil }
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func bitmapContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0,
              width <= Int.max / 4,
              height <= Int.max / (width * 4) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }

    /// Converts top-left coordinates to Quartz/Core Image's bottom-left coordinates.
    /// Round outward so no partially selected pixel escapes coverage.
    private func pixelRect(_ normalized: NormalizedRect, in bounds: CGRect) -> CGRect {
        let rectangle = normalized.rect(in: bounds)
        guard rectangle.width > 0, rectangle.height > 0 else { return .zero }
        let left = floor(rectangle.minX)
        let top = floor(rectangle.minY)
        let right = ceil(rectangle.maxX)
        let bottom = ceil(rectangle.maxY)
        return CGRect(x: left, y: bounds.height - bottom, width: right - left, height: bottom - top)
            .intersection(bounds)
    }
}
