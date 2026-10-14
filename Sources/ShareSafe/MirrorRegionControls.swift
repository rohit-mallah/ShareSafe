import SwiftUI
import ShareSafeCore

struct MirrorRegionControls: View {
    @ObservedObject var model: AppModel
    var showBlurControl = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(model.choosingCrop ? "Cancel region" : "Select region") {
                    if model.choosingCrop { model.finishCrop(nil) } else { model.beginCrop() }
                }.disabled(!model.canCrop || model.originalFrame == nil || model.isDrawing)
                Button("Full source") { model.setCrop(MirrorGeometry.full) }
                    .disabled(!model.canCrop || model.originalFrame == nil || model.choosingCrop)
                Spacer()
                if showBlurControl {
                    Button(model.fullOutputBlur ? "Restore output" : "Blur entire output") { model.toggleFullBlur() }
                        .help("Toggle audience-only blur (⌃⌥⌘F). Individual masks remain.")
                }
            }
            if model.canCrop && model.originalFrame != nil {
                HStack(spacing: 10) {
                    cropField("Left %", key: 0)
                    cropField("Top %", key: 1)
                    cropField("Width %", key: 2)
                    cropField("Height %", key: 3)
                }.disabled(model.choosingCrop || model.isDrawing)
                if model.selectedID?.hasPrefix("display:") == true { HStack {
                    TextField("Name this display region", text: $model.presetName).textFieldStyle(.roundedBorder)
                    Button("Save region") { model.saveRegion() }
                        .disabled(model.selectedID?.hasPrefix("display:") != true || model.presetName.trimmingCharacters(in: .whitespaces).isEmpty || model.choosingCrop)
                    if !model.savedRegions.isEmpty {
                        Menu("Saved regions") {
                            ForEach(model.savedRegions) { region in
                                Button("Restore “\(region.name)”") { model.restoreRegion(region) }
                                Button("Delete “\(region.name)”") { model.deleteRegion(region.id) }
                            }
                        }
                    }
                } }
            } else if !model.savedRegions.isEmpty {
                Menu("Saved display regions — select their display first") {
                    ForEach(model.savedRegions) { region in
                        Button("Restore “\(region.name)”") { model.restoreRegion(region) }
                        Button("Delete “\(region.name)”") { model.deleteRegion(region.id) }
                    }
                }
            }
        }.font(.system(size: 11))
    }

    private func cropField(_ title: String, key: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: Binding<Double>(get: {
                let c = model.crop
                return [c.x, c.y, c.width, c.height][key] * 100
            }, set: { value in
                guard value.isFinite else { return }
                let c = model.crop
                var values = [c.x, c.y, c.width, c.height]
                values[key] = min(1, max(key < 2 ? 0 : 0.01, value / 100))
                if key == 0 { values[0] = min(values[0], 1 - values[2]) }
                if key == 1 { values[1] = min(values[1], 1 - values[3]) }
                values[2] = min(values[2], 1 - values[0])
                values[3] = min(values[3], 1 - values[1])
                model.setCrop(NormalizedRect(x: values[0], y: values[1], width: values[2], height: values[3]))
            }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 52)
        }
    }
}
