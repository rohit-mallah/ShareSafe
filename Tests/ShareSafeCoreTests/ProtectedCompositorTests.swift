import CoreGraphics
import Foundation
import Testing
@testable import ShareSafeCore

struct ProtectedCompositorTests {
    @Test func combinesOnlySuppliedProcessedPixelsAndKeepsSourceImagesUnchanged() throws {
        let red = try image([255, 0, 0, 255])
        let blue = try image([0, 0, 255, 255])
        let mask = MaskRegion(rect: MirrorGeometry.full, style: .solid)
        let concealed = try #require(PrivacyRenderer().render(red, masks: [mask]))
        let output = try #require(ProtectedCompositor().render([concealed, blue], width: 20, height: 10))
        #expect(try pixel(output, x: 5, y: 5) == [0, 0, 0, 255])
        #expect(try pixel(output, x: 15, y: 5) == [0, 0, 255, 255])
        #expect(try pixel(red, x: 5, y: 5) == [255, 0, 0, 255])
    }

    @Test func emptyOrInvalidCompositeFailsInsteadOfCreatingUnprotectedOutput() throws {
        let compositor = ProtectedCompositor()
        #expect(compositor.render([]) == nil)
        #expect(compositor.render([try image([255, 0, 0, 255])], width: 0) == nil)
        #expect(compositor.render([try image([255, 0, 0, 255])], width: Int.max) == nil)
    }

    @Test func singleSourceKeepsAspectRatioWithOpaqueLetterboxing() throws {
        let output = try #require(ProtectedCompositor().render([image([255, 0, 0, 255])], width: 20, height: 10))
        #expect(try pixel(output, x: 10, y: 5) == [255, 0, 0, 255])
        let outside = try pixel(output, x: 0, y: 0)
        #expect(outside[0] < 20 && outside[1] < 20 && outside[2] < 20 && outside[3] == 255)
    }

    private func image(_ color: [UInt8]) throws -> CGImage {
        let data = Data(Array(repeating: color, count: 100).flatMap { $0 }) as CFData
        return try #require(CGImage(width: 10, height: 10, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 40, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: data + offset, count: 4))
    }
}
