import Testing
import CoreGraphics
@testable import ShareSafeCore

struct MirrorGeometryTests {
    @Test func cropsInward() {
        let crop = NormalizedRect(x: 0.101, y: 0.201, width: 0.5, height: 0.5)
        #expect(MirrorGeometry.pixelCrop(crop, width: 100, height: 100) == CGRect(x: 11, y: 21, width: 49, height: 49))
    }
    @Test func rejectsEmptyCrop() {
        #expect(MirrorGeometry.pixelCrop(NormalizedRect(x: 0, y: 0, width: 0, height: 1), width: 100, height: 100) == nil)
    }
    @Test func savedRegionRequiresSameDisplayGeometry() {
        let preset = SavedMirrorRegion(name: "Demo", sourceID: "display:1", sourceWidth: 1440, sourceHeight: 900, crop: MirrorGeometry.full)
        #expect(preset.matches(sourceID: "display:1", width: 1440, height: 900))
        #expect(!preset.matches(sourceID: "display:2", width: 1440, height: 900))
        #expect(!preset.matches(sourceID: "display:1", width: 1920, height: 1080))
    }
}
