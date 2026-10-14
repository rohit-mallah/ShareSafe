import CoreGraphics
import Foundation

public enum MirrorGeometry {
    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    /// Quartz image cropping uses top-left image coordinates. Round inward so
    /// pixels outside the selected source region never enter the mirror.
    public static func pixelCrop(_ crop: NormalizedRect, width: Int, height: Int) -> CGRect? {
        guard width > 0, height > 0 else { return nil }
        let rect = crop.rect(in: CGRect(x: 0, y: 0, width: width, height: height))
        let left = ceil(rect.minX), top = ceil(rect.minY)
        let right = floor(rect.maxX), bottom = floor(rect.maxY)
        guard right - left >= 2, bottom - top >= 2 else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    public static func crop(_ image: CGImage, to region: NormalizedRect) -> CGImage? {
        guard let rect = pixelCrop(region, width: image.width, height: image.height) else { return nil }
        return image.cropping(to: rect)
    }
}

public struct SavedMirrorRegion: Identifiable, Codable, Equatable {
    public let id: UUID
    public let name: String
    public let sourceID: String
    public let sourceWidth: Double
    public let sourceHeight: Double
    public let crop: NormalizedRect

    public init(name: String, sourceID: String, sourceWidth: Double, sourceHeight: Double, crop: NormalizedRect) {
        id = UUID()
        self.name = name
        self.sourceID = sourceID
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.crop = crop
    }

    public func matches(sourceID: String, width: Double, height: Double) -> Bool {
        self.sourceID == sourceID && sourceWidth == width && sourceHeight == height
            && MirrorGeometry.pixelCrop(crop, width: Int(max(0, min(width, 100_000))), height: Int(max(0, min(height, 100_000)))) != nil
    }
}
