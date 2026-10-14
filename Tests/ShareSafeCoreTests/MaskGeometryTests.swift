import CoreGraphics
import Foundation
import Testing
@testable import ShareSafeCore

struct MaskGeometryTests {
    @Test func testClipsPartialAndEntirelyOutsideRectangles() {
        let clipped = NormalizedRect(x: -0.2, y: 0.7, width: 0.8, height: 0.8)
        #expect(clipped.x == (0))
        #expect(clipped.y == (0.7))
        #expect(abs(clipped.width - 0.6) <= 0.000001)
        #expect(abs(clipped.height - 0.3) <= 0.000001)
        let outside = NormalizedRect(x: 2, y: -2, width: 0.5, height: 0.5)
        #expect(outside == (NormalizedRect(x: 1, y: 0, width: 0, height: 0)))
    }

    @Test func testNegativeDimensionsAreStandardized() {
        let rectangle = NormalizedRect(x: 0.8, y: 0.7, width: -0.3, height: -0.5)
        #expect(abs(rectangle.x - 0.5) <= 0.000001)
        #expect(abs(rectangle.y - 0.2) <= 0.000001)
        #expect(abs(rectangle.width - 0.3) <= 0.000001)
        #expect(abs(rectangle.height - 0.5) <= 0.000001)
    }

    @Test func testNonfiniteCoordinatesBecomeEmpty() {
        let empty = NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        #expect(NormalizedRect(x: .nan, y: 0, width: 1, height: 1) == (empty))
        #expect(NormalizedRect(x: 0, y: .infinity, width: 1, height: 1) == (empty))
        #expect(NormalizedRect(x: 0, y: 0, width: -.infinity, height: 1) == (empty))
        #expect(NormalizedRect(x: 0, y: 0, width: 1, height: .nan) == (empty))
    }

    @Test func testDecodingClampsInsteadOfBypassingInvariants() throws {
        let json = Data(#"{"x":-1,"y":0.5,"width":3,"height":2}"#.utf8)
        let rectangle = try JSONDecoder().decode(NormalizedRect.self, from: json)
        #expect(rectangle == (NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5)))
        let mask = MaskRegion(rect: rectangle, style: .blur)
        #expect((try JSONDecoder().decode(MaskRegion.self, from: JSONEncoder().encode(mask))) == (mask))
    }

    @Test func testInvertedDragAccountsForPreviewLetterboxing() throws {
        let bounds = CGRect(x: 20, y: 40, width: 200, height: 100)
        let rectangle = try #require(NormalizedRect.fromDrag(
            start: CGPoint(x: 180, y: 120), end: CGPoint(x: 60, y: 60), in: bounds
        ))
        #expect(abs(rectangle.x - 0.2) <= 0.000001)
        #expect(abs(rectangle.y - 0.2) <= 0.000001)
        #expect(abs(rectangle.width - 0.6) <= 0.000001)
        #expect(abs(rectangle.height - 0.6) <= 0.000001)
        let viewRectangle = rectangle.rect(in: bounds)
        #expect(abs(viewRectangle.minX - 60) <= 0.000001)
        #expect(abs(viewRectangle.minY - 60) <= 0.000001)
        #expect(abs(viewRectangle.width - 120) <= 0.000001)
        #expect(abs(viewRectangle.height - 60) <= 0.000001)
    }

    @Test func testDragClipsEndpointAndRejectsOutsideStartOrTinyGesture() throws {
        let bounds = CGRect(x: 10, y: 10, width: 100, height: 100)
        let clipped = try #require(NormalizedRect.fromDrag(
            start: CGPoint(x: 60, y: 60), end: CGPoint(x: 200, y: 200), in: bounds
        ))
        #expect(clipped == (NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        #expect(NormalizedRect.fromDrag(start: .zero, end: CGPoint(x: 60, y: 60), in: bounds) == nil)
        #expect(NormalizedRect.fromDrag(start: CGPoint(x: 60, y: 60), end: CGPoint(x: 62, y: 90), in: bounds) == nil)
        #expect(NormalizedRect.fromDrag(start: CGPoint(x: 60, y: 60), end: CGPoint(x: CGFloat.nan, y: 90), in: bounds) == nil)
        #expect(NormalizedRect.fromDrag(start: .zero, end: CGPoint(x: 30, y: 30), in: .zero) == nil)
    }

    @Test func testAspectFitLandscapeAndPortrait() {
        #expect(PreviewGeometry.aspectFit(source: CGSize(width: 200, height: 100), in: CGRect(x: 10, y: 20, width: 100, height: 100)) == (CGRect(x: 10, y: 45, width: 100, height: 50)))
        #expect(PreviewGeometry.aspectFit(source: CGSize(width: 100, height: 200), in: CGRect(x: 10, y: 20, width: 100, height: 100)) == (CGRect(x: 35, y: 20, width: 50, height: 100)))
        #expect(PreviewGeometry.aspectFit(source: .zero, in: CGRect(x: 0, y: 0, width: 10, height: 10)) == (.zero))
        #expect(PreviewGeometry.aspectFit(source: CGSize(width: CGFloat.infinity, height: 100), in: CGRect(x: 0, y: 0, width: 10, height: 10)) == (.zero))
    }
}
