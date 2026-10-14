import CoreGraphics
import Foundation
import Testing
@testable import ShareSafeCore

struct PrivacyRendererTests {
    private let renderer = PrivacyRenderer()

    @Test func testSolidCoverIsOpaqueAndLeavesEveryOutsidePixelUnchanged() throws {
        let input = try makeImage(width: 20, height: 16) { x, y in
            [UInt8(30 + x * 5), UInt8(40 + y * 8), 180, 255]
        }
        let mask = MaskRegion(rect: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let output = try #require(renderer.render(input, masks: [mask]))
        let original = try pixels(input)
        let result = try pixels(output)
        for y in 0..<16 {
            for x in 0..<20 {
                let expected: [UInt8] = (5..<15).contains(x) && (4..<12).contains(y)
                    ? [0, 0, 0, 255] : pixel(original, x: x, y: y, width: 20)
                #expect(pixel(result, x: x, y: y, width: 20) == (expected), "Pixel \(x),\(y)")
            }
        }
    }

    @Test func testTopLeftMaskCoversTopRowsNotBottomRowsAndRoundsOutward() throws {
        let input = try makeImage(width: 10, height: 10) { _, y in
            y < 5 ? [255, 0, 0, 255] : [0, 0, 255, 255]
        }
        let mask = MaskRegion(rect: NormalizedRect(x: 0.11, y: 0.01, width: 0.21, height: 0.21))
        let output = try pixels(#require(renderer.render(input, masks: [mask])))
        for y in 0..<10 {
            for x in 0..<10 {
                let expected: [UInt8] = (1..<4).contains(x) && y < 3
                    ? [0, 0, 0, 255] : (y < 5 ? [255, 0, 0, 255] : [0, 0, 255, 255])
                #expect(pixel(output, x: x, y: y, width: 10) == (expected), "Pixel \(x),\(y)")
            }
        }
    }

    @Test func testClippedMasksCoverOnlyImageIntersectionAndInvalidMasksDoNotCrash() throws {
        let input = try makeImage(width: 8, height: 8) { _, _ in [200, 100, 50, 255] }
        let masks = [
            MaskRegion(rect: NormalizedRect(x: -0.5, y: -0.5, width: 1, height: 1)),
            MaskRegion(rect: NormalizedRect(x: 2, y: 2, width: 1, height: 1)),
            MaskRegion(rect: NormalizedRect(x: .nan, y: 0, width: 1, height: 1))
        ]
        let output = try pixels(#require(renderer.render(input, masks: masks)))
        for y in 0..<8 {
            for x in 0..<8 {
                #expect(pixel(output, x: x, y: y, width: 8) == (x < 4 && y < 4 ? [0, 0, 0, 255] : [200, 100, 50, 255]))
            }
        }
    }

    @Test func testBlurChangesCoveredDetailWithoutChangingOutsidePixels() throws {
        let input = try makeImage(width: 64, height: 64) { x, y in
            (x + y).isMultiple(of: 2) ? [255, 255, 255, 255] : [0, 0, 0, 255]
        }
        // Asymmetric vertical placement also checks Core Image's coordinate conversion.
        let mask = MaskRegion(rect: NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 0.5), style: .blur)
        let output = try pixels(#require(renderer.render(input, masks: [mask])))
        let original = try pixels(input)
        var changed = 0
        for y in 0..<64 {
            for x in 0..<64 {
                let actual = pixel(output, x: x, y: y, width: 64)
                let before = pixel(original, x: x, y: y, width: 64)
                if (16..<48).contains(x) && y < 32 {
                    if actual != before { changed += 1 }
                    #expect(actual[3] == (255))
                } else {
                    #expect(actual == (before), "Outside blur at \(x),\(y)")
                }
            }
        }
        #expect(changed > 900)
    }

    @Test func testSolidCoverWinsOverOverlappingBlurRegardlessOfOrder() throws {
        let input = try makeImage(width: 32, height: 32) { _, _ in [255, 100, 200, 255] }
        let solid = MaskRegion(rect: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let blur = MaskRegion(rect: NormalizedRect(x: 0, y: 0, width: 1, height: 1), style: .blur)
        for masks in [[solid, blur], [blur, solid]] {
            let output = try pixels(#require(renderer.render(input, masks: masks)))
            for y in 8..<24 {
                for x in 8..<24 {
                    #expect(pixel(output, x: x, y: y, width: 32) == ([0, 0, 0, 255]))
                }
            }
        }
    }

    @Test func testBlankIsOpaqueAcrossAllPixelsAndInvalidDimensionsFail() throws {
        let image = try #require(renderer.blank(width: 37, height: 21))
        #expect(image.width == (37))
        #expect(image.height == (21))
        let output = try pixels(image)
        for offset in stride(from: 0, to: output.count, by: 4) {
            #expect(Array(output[offset..<(offset + 4)]) == ([0, 0, 0, 255]))
        }
        #expect(renderer.blank(width: 0, height: 10) == nil)
        #expect(renderer.blank(width: 10, height: -1) == nil)
        #expect(renderer.blank(width: Int.max, height: 10) == nil)
    }

    private func makeImage(width: Int, height: Int, color: (Int, Int) -> [UInt8]) throws -> CGImage {
        var bytes = [UInt8]()
        for y in 0..<height {
            for x in 0..<width { bytes.append(contentsOf: color(x, y)) }
        }
        let data = Data(bytes) as CFData
        let provider = try #require(CGDataProvider(data: data))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    private func pixel(_ bytes: [UInt8], x: Int, y: Int, width: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
