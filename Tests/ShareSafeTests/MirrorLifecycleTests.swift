import Testing
import Foundation
import ShareSafeCore
@testable import ShareSafe

@MainActor
struct MirrorLifecycleTests {
    private func ready(_ model: AppModel) async throws {
        for _ in 0..<200 {
            if model.originalFrame != nil && !model.isLoading { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("Demo did not become ready")
    }

    @Test func sourceSelectionNeverRestoresCropRelativeMasksOntoFullSource() async throws {
        let model = AppModel()
        model.selectDemo()
        try await ready(model)
        model.setCrop(NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
        model.beginMask()
        model.finishMask(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        #expect(model.masks.count == 1)
        model.goLive()
        #expect(model.audienceFrame != nil)
        model.selectDemo()
        #expect(model.audienceFrame == nil && !model.outputEnabled)
        try await ready(model)
        #expect(model.crop == MirrorGeometry.full)
        #expect(model.masks.isEmpty)
        model.stop()
    }

    @Test func editingCropPausesOutputAndResetsMasks() async throws {
        let model = AppModel()
        model.selectDemo()
        try await ready(model)
        let expectedWidth = try #require(model.originalFrame).width / 2
        model.goLive()
        model.beginCrop()
        #expect(!model.canGoLive && !model.outputEnabled && model.audienceFrame == nil)
        model.finishCrop(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(model.originalFrame?.width == expectedWidth)
        #expect(model.canGoLive && !model.outputEnabled)
        model.stop()
    }

    @Test func rejectedCropRestoresPreviousRegionInsteadOfFullSource() async throws {
        let model = AppModel()
        model.selectDemo()
        try await ready(model)
        let expectedWidth = try #require(model.originalFrame).width / 2
        let previous = NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
        model.setCrop(previous)
        model.beginCrop()
        model.finishCrop(NormalizedRect(x: 0, y: 0, width: 0.00001, height: 1))
        #expect(model.crop == previous)
        #expect(model.originalFrame?.width == expectedWidth)
        #expect(model.canGoLive && !model.outputEnabled)
        model.stop()
    }

    @Test func wholeOutputBlurPreservesOriginalAndIndividualMasks() async throws {
        let model = AppModel()
        model.selectDemo()
        try await ready(model)
        let original = model.originalFrame
        model.beginMask()
        model.finishMask(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        model.goLive()
        model.toggleFullBlur()
        #expect(model.fullOutputBlur && model.masks.count == 1)
        #expect(model.originalFrame === original && model.audienceFrame != nil)
        model.toggleFullBlur()
        #expect(!model.fullOutputBlur && model.masks.count == 1)
        #expect(!model.outputEnabled && model.audienceFrame == nil)
        model.stop()
        #expect(model.audienceFrame == nil && model.originalFrame == nil)
    }
}
