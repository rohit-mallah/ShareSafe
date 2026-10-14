import CoreGraphics
import Foundation

/// A clipped rectangle in source-relative coordinates, with the origin at the top left.
public struct NormalizedRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else {
            self.x = 0
            self.y = 0
            self.width = 0
            self.height = 0
            return
        }
        let left = Self.unit(min(x, x + width))
        let top = Self.unit(min(y, y + height))
        let right = Self.unit(max(x, x + width))
        let bottom = Self.unit(max(y, y + height))
        self.x = left
        self.y = top
        self.width = right - left
        self.height = bottom - top
    }

    /// Drags must begin in the image. Their endpoint is clipped to it.
    /// Gestures smaller than three view points on either axis do not create masks.
    public static func fromDrag(start: CGPoint, end: CGPoint, in contentRect: CGRect) -> NormalizedRect? {
        guard contentRect.hasFinitePositiveSize,
              start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
              start.x >= contentRect.minX, start.x <= contentRect.maxX,
              start.y >= contentRect.minY, start.y <= contentRect.maxY else { return nil }
        let endpoint = CGPoint(
            x: min(max(end.x, contentRect.minX), contentRect.maxX),
            y: min(max(end.y, contentRect.minY), contentRect.maxY)
        )
        let left = min(start.x, endpoint.x)
        let top = min(start.y, endpoint.y)
        let width = abs(endpoint.x - start.x)
        let height = abs(endpoint.y - start.y)
        guard width >= 3, height >= 3 else { return nil }
        return NormalizedRect(
            x: (left - contentRect.minX) / contentRect.width,
            y: (top - contentRect.minY) / contentRect.height,
            width: width / contentRect.width,
            height: height / contentRect.height
        )
    }

    public func rect(in bounds: CGRect) -> CGRect {
        guard bounds.hasFinitePositiveSize else { return .zero }
        return CGRect(
            x: bounds.minX + x * bounds.width,
            y: bounds.minY + y * bounds.height,
            width: width * bounds.width,
            height: height * bounds.height
        )
    }

    private static func unit(_ value: Double) -> Double { min(max(value, 0), 1) }

    private enum CodingKeys: String, CodingKey { case x, y, width, height }

    // Decoded documents must satisfy the same invariants as interactive masks.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try values.decode(Double.self, forKey: .x),
            y: try values.decode(Double.self, forKey: .y),
            width: try values.decode(Double.self, forKey: .width),
            height: try values.decode(Double.self, forKey: .height)
        )
    }
}

public enum MaskStyle: String, Codable, CaseIterable, Sendable {
    case solid
    case blur

    public var label: String {
        switch self {
        case .solid: return "Solid cover"
        case .blur: return "Blur"
        }
    }
}

public struct MaskRegion: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var rect: NormalizedRect
    public var style: MaskStyle

    public init(id: UUID = UUID(), rect: NormalizedRect, style: MaskStyle = .solid) {
        self.id = id
        self.rect = rect
        self.style = style
    }
}

public enum PreviewGeometry {
    public static func aspectFit(source: CGSize, in bounds: CGRect) -> CGRect {
        guard source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0,
              bounds.hasFinitePositiveSize else { return .zero }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        guard scale.isFinite else { return .zero }
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private extension CGRect {
    var hasFinitePositiveSize: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
            && maxX.isFinite && maxY.isFinite && width > 0 && height > 0
    }
}
