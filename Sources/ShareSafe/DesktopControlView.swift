import AppKit
import SwiftUI
import ShareSafeCore

struct DesktopControlView: View {
    @ObservedObject var overlays: DesktopOverlayController
    let hideArea: () -> Void
    let editCovers: () -> Void
    let openChrome: () -> Void
    let openMirror: () -> Void
    let shortcutWarning: String?

    private let mint = Color(red: 0.40, green: 0.88, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 29, weight: .light)).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ShareSafe").font(.system(size: 25, weight: .semibold))
                    Text("Direct Blur · share your screen as usual.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                Button(action: hideArea) {
                    HStack {
                        Image(systemName: "plus.rectangle.dashed")
                        Text("Hide an area").fontWeight(.semibold)
                        Spacer()
                        Text("⌃⌥⌘H").font(.system(size: 12, design: .monospaced))
                    }.padding(.vertical, 8).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(overlays.emergencyCovered)
                Text("Drag over any part of your desktop. Press Escape to cancel.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }

            Picker("New area style", selection: $overlays.maskStyle) {
                ForEach(MaskStyle.allCases, id: \.self) { style in Text(style.label).tag(style) }
            }.pickerStyle(.segmented)
            Button(action: openMirror) {
                Label("Mirror Share — keep my workspace clear", systemImage: "macwindow.on.rectangle")
            }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(overlays.emergencyCovered ? Color.orange : mint)
                        .frame(width: 7, height: 7)
                    Text(overlays.emergencyCovered ? "All displays covered" : "\(overlays.regionCount) area\(overlays.regionCount == 1 ? "" : "s") covered")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if overlays.isEditing { Text("Editing").font(.system(size: 11)).foregroundStyle(mint) }
                }
                HStack(spacing: 10) {
                    Button(overlays.isEditing ? "Finish editing" : "Move / remove") { editCovers() }
                        .disabled(overlays.regionCount == 0 || overlays.emergencyCovered)
                    Button("Undo") { overlays.undo() }
                        .disabled(overlays.regionCount == 0 || overlays.emergencyCovered)
                    Spacer()
                    Button("Clear covers") { overlays.removeAll() }
                        .disabled(overlays.regionCount == 0 || overlays.emergencyCovered)
                }.controlSize(.small)
                Text(overlays.isEditing ? "Drag a cover to move it. Right-click to remove it. Escape finishes editing." : "\(overlays.status)")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("In Meet, Zoom or Teams").font(.system(size: 13, weight: .semibold))
                Text("Share your entire screen with the meeting’s normal Share button. Blur appears on your Mac too. For audience-only blur, use Mirror Share.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                Text("Sharing only a tab or an app can omit desktop covers. Use the Chrome companion for webpage content.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Button(action: openChrome) {
                    Label("Set up Chrome companion", systemImage: "arrow.up.forward.app")
                }.buttonStyle(.link).font(.system(size: 12))
            }

            if let error = overlays.lastError ?? shortcutWarning {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineSpacing(3)
            }

            Spacer(minLength: 0)
            Button { overlays.toggleEmergencyCover() } label: {
                HStack {
                    Image(systemName: overlays.emergencyCovered ? "rectangle.slash" : "shield.fill")
                    Text(overlays.emergencyCovered ? "Restore desktop" : "Cover all displays")
                    Spacer()
                    Text("⌃⌥⌘B").font(.system(size: 11, design: .monospaced))
                }.padding(.vertical, 6)
            }.controlSize(.large)
            Text("Native desktop blur needs no Screen Recording permission. Reduce transparency uses solid covers. Test the receiver view before presenting.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
        }
        .padding(26)
        .frame(width: 440, height: 730)
        .background(Color(red: 0.065, green: 0.08, blue: 0.095))
        .preferredColorScheme(.dark)
        .tint(mint)
    }
}
