import CoreGraphics
import Testing
@testable import ShareSafeCore

struct PresenterGeometryTests {
    @Test func retinaContentMustFillTheBufferBeforeOriginalOutlinesAreAllowed() {
        #expect(PresenterGeometry.contentFillsBuffer(CGRect(x: 0, y: 0, width: 960, height: 540),
            scale: 2, width: 1920, height: 1080))
        // A square output buffer after the source becomes a landscape window.
        #expect(!PresenterGeometry.contentFillsBuffer(CGRect(x: 0, y: 250, width: 1000, height: 500),
            scale: 1, width: 1000, height: 1000))
        #expect(!PresenterGeometry.contentFillsBuffer(CGRect(x: 250, y: 0, width: 500, height: 1000),
            scale: 1, width: 1000, height: 1000))
    }

    @Test func unknownOrInvalidGeometrySuppressesOutlines() {
        #expect(!PresenterGeometry.contentFillsBuffer(.zero, scale: 1, width: 100, height: 100))
        #expect(!PresenterGeometry.contentFillsBuffer(CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: .nan, width: 100, height: 100))
        #expect(!PresenterGeometry.contentFillsBuffer(CGRect(x: 0, y: 0, width: 90, height: 100),
            scale: 1, width: 100, height: 100))
    }
}
