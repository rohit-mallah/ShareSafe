import Testing
import CoreGraphics
import Foundation
@testable import ShareSafeCore

struct CropPixelTests {
    @Test func imageCropUsesTopLeftCoordinatesAndExcludesOutsideRows() throws {
        var bytes: [UInt8] = []
        for y in 0..<8 {
            for _ in 0..<8 { bytes += y < 4 ? [255, 0, 0, 255] : [0, 0, 255, 255] }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let input = try #require(CGImage(width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let crop = try #require(MirrorGeometry.crop(input, to: NormalizedRect(x: 0, y: 0, width: 1, height: 0.5)))
        #expect(crop.width == 8 && crop.height == 4)
        let context = try #require(CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 8, height: 4))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for i in stride(from: 0, to: 128, by: 4) {
            #expect(pixels[i] == 255 && pixels[i + 1] == 0 && pixels[i + 2] == 0 && pixels[i + 3] == 255)
        }
    }
}
