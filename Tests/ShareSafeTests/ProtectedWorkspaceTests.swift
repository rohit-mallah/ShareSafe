import Testing
import Foundation
import CoreGraphics
import ShareSafeCore
@testable import ShareSafe

@MainActor
struct ProtectedWorkspaceTests {
    private func ready(_ source: ProtectedSource) async throws {
        for _ in 0..<200 {
            if source.model.originalFrame != nil && !source.model.isLoading { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("Fictional source did not load")
    }

    @Test func twoSourcesKeepIndependentMasksWhenSelected() async throws {
        let workspace = ProtectedWorkspaceModel()
        defer { workspace.stop() }
        let first = workspace.addDemo()
        try await ready(first)
        let original = try #require(first.model.originalFrame)
        first.model.beginMask()
        first.model.finishMask(NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let second = workspace.addDemo()
        try await ready(second)
        second.model.beginMask()
        second.model.finishMask(NormalizedRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2))
        workspace.select(first.id)
        #expect(first.model.masks.count == 1 && second.model.masks.count == 1)
        #expect(first.model.masks[0].rect != second.model.masks[0].rect)
        #expect(first.model.originalFrame === original)
        #expect(workspace.selected === first && !workspace.outputEnabled)
    }

    @Test func removingMaskImmediatelyPausesWholeGridBeforeRevealing() async throws {
        let workspace = ProtectedWorkspaceModel()
        defer { workspace.stop() }
        let first = workspace.addDemo()
        let second = workspace.addDemo()
        try await ready(first)
        try await ready(second)
        first.model.maskStyle = .solid
        first.model.beginMask()
        first.model.finishMask(MirrorGeometry.full)
        workspace.setLayout(.grid)
        workspace.goLive()
        #expect(workspace.outputEnabled && workspace.audienceFrame != nil)
        first.model.removeMask(try #require(first.model.masks.first).id)
        #expect(!workspace.outputEnabled && workspace.audienceFrame == nil)
        #expect(!first.model.outputEnabled && !second.model.outputEnabled)
    }

    @Test func removedSourcesCannotResumeOrPublishIntoSession() async throws {
        let workspace = ProtectedWorkspaceModel()
        let first = workspace.addDemo()
        let second = workspace.addDemo()
        try await ready(first)
        try await ready(second)
        workspace.goLive()
        workspace.remove(first.id)
        #expect(!workspace.outputEnabled && workspace.audienceFrame == nil)
        #expect(first.model.originalFrame == nil)
        #expect(workspace.sources.count == 1 && workspace.selected === second)
        // Simulates a caller still holding the removed model. Its former callbacks
        // must not affect a newly resumed workspace.
        workspace.goLive()
        #expect(workspace.outputEnabled)
        first.model.selectDemo()
        try await ready(first)
        first.model.goLive()
        first.model.clearMasks()
        #expect(workspace.outputEnabled && workspace.audienceFrame != nil)
        first.model.stop()
        workspace.stop()
        #expect(workspace.sources.isEmpty && workspace.audienceFrame == nil)
    }

    @Test func switchingDuringDrawingCancelsGestureAndKeepsSessionPaused() async throws {
        let workspace = ProtectedWorkspaceModel()
        defer { workspace.stop() }
        let first = workspace.addDemo()
        let second = workspace.addDemo()
        try await ready(first)
        try await ready(second)
        workspace.select(first.id)
        workspace.goLive()
        first.model.beginMask()
        #expect(!workspace.outputEnabled && workspace.audienceFrame == nil)
        workspace.select(second.id)
        #expect(!first.model.isDrawing && first.model.masks.isEmpty)
        #expect(workspace.canGoLive && !workspace.outputEnabled)
    }

    @Test func sourceFailureAndLayoutChangesNeverRetainOldOutput() async throws {
        let workspace = ProtectedWorkspaceModel()
        defer { workspace.stop() }
        let first = workspace.addDemo()
        let second = workspace.addDemo()
        try await ready(first)
        try await ready(second)
        workspace.goLive()
        workspace.setLayout(.grid)
        #expect(!workspace.outputEnabled && workspace.audienceFrame == nil)
        workspace.goLive()
        second.model.stop()
        #expect(!workspace.outputEnabled && workspace.audienceFrame == nil)
        #expect(!workspace.canGoLive)
        #expect(workspace.protectedPreview() == nil)
    }

    @Test func addingSourceDuringCropOrDrawingCancelsHiddenEditor() async throws {
        let workspace = ProtectedWorkspaceModel()
        defer { workspace.stop() }
        let first = workspace.addDemo()
        try await ready(first)
        first.model.beginCrop()
        #expect(first.model.choosingCrop)
        let second = workspace.addDemo()
        try await ready(second)
        #expect(!first.model.choosingCrop && workspace.canGoLive)
        second.model.beginMask()
        let third = workspace.addDemo()
        try await ready(third)
        #expect(!second.model.isDrawing && second.model.masks.isEmpty)
        #expect(workspace.canGoLive && !workspace.outputEnabled)
    }

    @Test func fullAudienceBlurPreservesPrivateOriginalsAndMasks() async throws {
        let workspace = ProtectedWorkspaceModel()
        defer { workspace.stop() }
        let source = workspace.addDemo()
        try await ready(source)
        let original = source.model.originalFrame
        source.model.beginMask()
        source.model.finishMask(NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4))
        workspace.goLive()
        workspace.toggleFullBlur()
        #expect(workspace.fullOutputBlur && workspace.audienceFrame != nil)
        #expect(source.model.originalFrame === original && source.model.masks.count == 1)
        workspace.toggleFullBlur()
        #expect(!workspace.fullOutputBlur && !workspace.outputEnabled && workspace.audienceFrame == nil)
    }
}
