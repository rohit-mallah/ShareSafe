import SwiftUI
import ShareSafeCore

private let protectedMint = Color(red: 0.40, green: 0.88, blue: 0.72)

struct ProtectedControlView: View {
    @ObservedObject var workspace: ProtectedWorkspaceModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 242)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if let source = workspace.selected {
                    ProtectedSourceEditor(model: source.model, workspace: workspace).id(source.id)
                } else {
                    emptyState
                }
                Divider()
                footer
            }
        }
        .background(Color(red: 0.065, green: 0.08, blue: 0.10))
        .preferredColorScheme(.dark).tint(protectedMint)
        .frame(minWidth: 1050, minHeight: 740)
        .sheet(isPresented: $workspace.showHelp) { help }
        .sheet(isPresented: $workspace.showLegacySources) { legacyPicker }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.badge.checkmark").foregroundStyle(protectedMint)
                Text("ShareSafe").font(.system(size: 24, weight: .semibold, design: .rounded))
            }.padding(.top, 8)
            Text("PROTECTED WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
            Button { workspace.chooseSource() } label: {
                Label("Add window", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("add-source")
            Button { workspace.loadLegacySources(displaysOnly: true) } label: {
                Label("Add screen", systemImage: "display").frame(maxWidth: .infinity)
            }.controlSize(.large).disabled(workspace.isLoadingSources)
            Text("Add more than one. Each keeps its own masks.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(workspace.sources) { source in
                        HStack(alignment: .top, spacing: 8) {
                            Button { workspace.select(source.id) } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: source.captureSource?.kind == .display ? "display" : "macwindow")
                                        .foregroundStyle(workspace.selectedID == source.id ? protectedMint : .secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(source.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        Text(source.model.isLoading ? "Connecting…" : source.model.errorMessage != nil ? "Needs attention" : "\(source.model.masks.count) private areas")
                                            .font(.system(size: 10)).foregroundStyle(source.model.errorMessage != nil ? .orange : .secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Button { workspace.remove(source.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove \(source.title)")
                        }.padding(10)
                            .background(workspace.selectedID == source.id ? protectedMint.opacity(0.09) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            Button("Add demo source") { workspace.addDemo() }.accessibilityIdentifier("add-demo")
            Button(workspace.isLoadingSources ? "Loading…" : "Advanced source list…") { workspace.loadLegacySources() }
                .disabled(workspace.isLoadingSources).font(.system(size: 11))
            Text("The advanced list requires Screen Recording permission. No camera or microphone is needed.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            Divider()
            Label("Local processing. No recordings.", systemImage: "lock.shield")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(18).background(.black.opacity(0.14))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(workspace.selected?.title ?? "Your workspace stays clear")
                    .font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Text("Share the separate Protected View window in your meeting.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Label(workspace.outputEnabled ? "Output running" : "Output paused", systemImage: workspace.outputEnabled ? "circle.fill" : "pause.circle")
                .foregroundStyle(workspace.outputEnabled ? protectedMint : .orange).font(.system(size: 11, weight: .medium))
            Button { workspace.showHelp = true } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.plain)
        }.padding(24)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "macwindow.on.rectangle").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(protectedMint)
            Text("Clear for you. Private for your audience.").font(.system(size: 25, weight: .medium))
            Text("Add windows or screens, draw privacy areas,\nthen share the protected window once.")
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            HStack(spacing: 12) {
                Button("Add window") { workspace.chooseSource() }.buttonStyle(.borderedProminent)
                Button("Add screen") { workspace.loadLegacySources(displaysOnly: true) }.buttonStyle(.bordered)
                Button("Try with demo data") { workspace.addDemo() }.buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = workspace.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workspace.message).font(.system(size: 11)).lineLimit(3)
                    Text("Emergency pause: ⌃⌥⌘B").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Open protected view") { workspace.showAudience?() }
                Button("Share in meeting…") { workspace.requestSharing?() }.disabled(!workspace.outputEnabled)
                Button(workspace.outputEnabled ? "Pause output" : "Start protected output") { workspace.toggleOutput() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!workspace.outputEnabled && !workspace.canGoLive).accessibilityIdentifier("toggle-output")
            }
        }.padding(20)
    }

    private var legacyPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add a window or display").font(.title2)
                Spacer()
                Button("Done") { workspace.showLegacySources = false }
            }
            Text("This list uses Screen Recording access so ShareSafe can exclude its own private controls from display capture.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workspace.legacySources) { source in
                        Button { workspace.add(source) } label: {
                            HStack {
                                Image(systemName: source.kind == .display ? "display" : "macwindow")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.title)
                                    Text(source.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                            }.padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(24).frame(width: 600, height: 520).preferredColorScheme(.dark)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Share the protected copy").font(.system(size: 26, weight: .semibold))
            Text("1. Add each window or screen you want to present.\n2. Draw private areas in the clear preview.\n3. Start protected output.\n4. In Meet, Zoom or Teams, share the window named ShareSafe Protected View — Share this window.")
                .font(.system(size: 14)).lineSpacing(8)
            Text("Your original apps remain readable and interactive. Green outlines mark areas in ShareSafe’s private preview. Sharing your physical screen or these controls bypasses the protection.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            Text("Browser windows work without an extension. For independent tab masks, move tabs into separate windows. Rectangles stay at source coordinates; they do not follow webpage content while scrolling.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Text("The system picker authorizes selected content for this session. Advanced display capture needs Screen Recording permission to safely exclude ShareSafe’s controls. Camera, microphone and audio capture are disabled.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            Button("Got it") { workspace.showHelp = false }.buttonStyle(.borderedProminent)
        }.padding(30).frame(width: 640).preferredColorScheme(.dark)
    }
}

private struct ProtectedSourceEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: ProtectedWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("YOUR CLEAR PREVIEW", systemImage: "eye").font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Text(model.choosingCrop ? "Drag the region to share" : "Drag to mark a private area")
                    .font(.system(size: 11)).foregroundStyle(protectedMint)
            }.foregroundStyle(.secondary)
            ZStack {
                PreviewCanvas(model: model)
                if model.originalFrame == nil {
                    VStack(spacing: 12) {
                        if model.isLoading { ProgressView() }
                        Text(model.isLoading ? "Connecting to your source…" : "Source unavailable")
                    }.foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            MirrorRegionControls(model: model, showBlurControl: false)
            HStack(spacing: 12) {
                Picker("Privacy style", selection: $model.maskStyle) {
                    ForEach(MaskStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(width: 190)
                Text("\(model.masks.count) private areas").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Undo") { if let last = model.masks.last { model.removeMask(last.id) } }.disabled(model.masks.isEmpty)
                Button("Clear") { model.clearMasks() }.disabled(model.masks.isEmpty)
            }
            if let error = model.errorMessage {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                    Button("Screen settings") { model.openScreenRecordingSettings() }
                }
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AUDIENCE PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    Text("Only this processed copy goes into the Protected View.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("Output layout", selection: Binding(get: { workspace.layout }, set: { workspace.setLayout($0) })) {
                        ForEach(ProtectedLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Button(workspace.fullOutputBlur ? "Restore normal output" : "Blur entire audience view") { workspace.toggleFullBlur() }
                }
                ZStack {
                    Color.black
                    if let image = workspace.outputEnabled ? workspace.audienceFrame : workspace.protectedPreview() {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                    } else {
                        Text("Waiting for protected pixels").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(width: 250, height: 141).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("Areas stay fixed within this source. Review them after scrolling. Use solid covers for secrets that must be unreadable.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(20)
    }
}

struct ProtectedAudienceView: View {
    @ObservedObject var workspace: ProtectedWorkspaceModel
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.055)
            if let image = workspace.audienceFrame {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "pause.rectangle").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(protectedMint)
                    Text("Presentation paused").font(.system(size: 24, weight: .medium))
                    Text("The presenter will be right back.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).preferredColorScheme(.dark)
    }
}
