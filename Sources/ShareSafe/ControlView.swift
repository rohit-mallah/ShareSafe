import SwiftUI
import ShareSafeCore

private let mint = Color(red: 0.40, green: 0.88, blue: 0.72)
private let surface = Color(red: 0.075, green: 0.09, blue: 0.11)

struct ControlView: View {
    @ObservedObject var model: AppModel
    var showDirect: (() -> Void)?
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 245)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                workspace.padding(24)
                Divider()
                bottomBar
            }
        }
        .background(surface)
        .preferredColorScheme(.dark)
        .tint(mint)
        .frame(minWidth: 1030, minHeight: 700)
        .sheet(isPresented: $model.showHelp) { help }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.inset.filled.and.person.filled").font(.system(size: 23)).foregroundStyle(mint)
                Text("ShareSafe").font(.system(size: 23, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 22).padding(.top, 28)
            Text("YOUR SCREEN. YOUR CHOICE.")
                .font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 32)
            HStack {
                Text("SOURCES").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                Button { model.refreshSources() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(model.isLoading).help("Refresh windows and displays (⌘R)")
            }.padding(.horizontal, 22)
            TextField("Find a window…", text: $model.search)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.filteredSources) { source in
                        Button { model.select(source) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: source.kind == .display ? "display" : "macwindow")
                                    .font(.system(size: 17)).foregroundStyle(model.selectedID == source.id ? mint : .secondary)
                                    .frame(width: 22).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(source.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if model.selectedID == source.id { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(mint) }
                            }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.selectedID == source.id ? mint.opacity(0.09) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).accessibilityLabel("Capture \(source.title)")
                    }
                    if model.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bring a window into view.").font(.system(size: 12, weight: .medium))
                            Text("Load your open windows and displays to choose a source.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                            Button("Load sources") { model.refreshSources() }.disabled(model.isLoading)
                        }.padding(12)
                    }
                }.padding(.horizontal, 10)
            }
            if let showDirect { Button("← Direct Blur", action: showDirect).padding(18) }
            Divider().padding(.horizontal, 20)
            Button { model.selectDemo() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle").foregroundStyle(mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Try the demo").font(.system(size: 12, weight: .medium))
                        Text("Practice with fictional data").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(18)
            }.buttonStyle(.plain)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").foregroundStyle(mint)
                Text("On your Mac. No uploads.").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.bottom, 23)
        }.background(Color.black.opacity(0.13))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.sourceTitle).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Text("Private controls · share the separate Mirror")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.outputEnabled && !model.isDrawing ? mint : Color.orange.opacity(0.8)).frame(width: 6, height: 6)
                Text(model.outputLabel).font(.system(size: 11, weight: .medium))
            }
            Button { model.showHelp = true } label: { Image(systemName: "questionmark.circle").font(.system(size: 17)) }
                .buttonStyle(.plain).help("How to share safely")
        }.padding(.horizontal, 26).padding(.vertical, 24)
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("PRIVATE PREVIEW", systemImage: "eye").font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
                Spacer()
                if model.originalFrame != nil {
                    Text(model.choosingCrop ? "Drag the region to share" : "Drag a rectangle to blur private details").font(.system(size: 11)).foregroundStyle(mint)
                }
            }
            ZStack {
                PreviewCanvas(model: model)
                if model.originalFrame == nil {
                    VStack(spacing: 18) {
                        if model.isLoading {
                            ProgressView().controlSize(.large)
                            Text("Preparing your source…").font(.system(size: 17, weight: .medium))
                        } else {
                            Image(systemName: "macwindow.on.rectangle").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(mint.opacity(0.85))
                            Text("Share only what matters.").font(.system(size: 25, weight: .medium))
                            Text("Choose a source, cover private details,\nthen share your Mirror.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                            HStack(spacing: 12) {
                                Button("Choose a source") { model.refreshSources() }.buttonStyle(.borderedProminent)
                                Button("Try demo") { model.selectDemo() }.buttonStyle(.bordered)
                            }.padding(.top, 5)
                        }
                    }.padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.07), lineWidth: 1))

            MirrorRegionControls(model: model)
            HStack(spacing: 16) {
                Label("Mask", systemImage: "rectangle.dashed").font(.system(size: 12, weight: .medium))
                Picker("Mask style", selection: $model.maskStyle) {
                    ForEach(MaskStyle.allCases, id: \.self) { style in Text(style.label).tag(style) }
                }.pickerStyle(.segmented).frame(width: 174)
                Spacer()
                Text("\(model.masks.count) region\(model.masks.count == 1 ? "" : "s") hidden")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Clear all") { model.clearMasks() }.disabled(model.masks.isEmpty).controlSize(.small)
            }
            if !model.masks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.masks.enumerated()), id: \.element.id) { index, mask in
                            HStack(spacing: 8) {
                                Text("\(index+1) · \(mask.style.label)").font(.system(size: 11))
                                Button { model.removeMask(mask.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                                    .buttonStyle(.plain).help("Remove mask \(index+1) and reveal this region")
                            }.padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.06)).clipShape(Capsule())
                        }
                    }
                }.frame(height: 29)
            }
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(error).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(4)
                        Button("Open Screen Recording settings") { model.openScreenRecordingSettings() }.controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }.padding(12).background(Color.orange.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Text(model.maskStyle == .blur ? "Blur softens content. Use solid covers for passwords or confidential text." : "Masks stay in place within the source. Check them after scrolling or changing the layout.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.message).font(.system(size: 11)).lineLimit(2)
                Text("Emergency blank: ⌃⌥⌘B").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            Button("Mirror") { model.showAudience?() }.controlSize(.large)
            Button {
                model.toggleOutput()
            } label: {
                Label(model.outputEnabled ? "Blank output" : "Go live", systemImage: model.outputEnabled ? "pause.fill" : "play.fill")
                    .frame(minWidth: 98)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.outputEnabled && !model.canGoLive)
        }.padding(.horizontal, 24).padding(.vertical, 17)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("One window. A private presentation.").font(.system(size: 23, weight: .semibold))
                Spacer()
                Button { model.showHelp = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19)) }.buttonStyle(.plain)
            }
            helpStep("1", "Choose a source", "Load your windows, approve Screen Recording if macOS asks, and select one. Use a separate browser window for the tabs you plan to show.")
            helpStep("2", "Cover private details", "Drag rectangles in this private preview. Your original app stays clear. Blur is the default; solid masks remain available.")
            helpStep("3", "Share the Mirror", "Choose Go live. In your meeting app, share the window named ShareSafe Mirror — Share this window. Keep this output window open and unminimized.")
            helpStep("4", "Switch without re-sharing", "Pick another source here. The audience pauses while you review its masks. Choose Go live to continue in the same shared window.")
            Divider()
            Text("Sharing your physical display or these private controls bypasses protection. Meeting apps must support sharing an individual window. Compatibility with each Meet, Zoom, Teams and WhatsApp client still needs a receiver-side test.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack {
                Text("Prototype · local processing · video only").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Got it") { model.showHelp = false }.buttonStyle(.borderedProminent)
            }
        }.padding(30).frame(width: 620).preferredColorScheme(.dark)
    }
    private func helpStep(_ number: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Text(number).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(mint).frame(width: 23)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }
}

struct AudienceView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.055, blue: 0.07)
            if let frame = model.audienceFrame {
                Image(decorative: frame, scale: 1).resizable().interpolation(.high).scaledToFit()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "pause.rectangle").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(mint)
                    Text("Presentation paused").font(.system(size: 24, weight: .medium))
                    Text("The presenter will be right back.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).preferredColorScheme(.dark)
    }
}
