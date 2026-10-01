import AppKit
import SwiftUI
import WebKit

struct PreviewPane: View {
    @ObservedObject var renderer: MermaidRenderer

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                Color(nsColor: .textBackgroundColor)

                MermaidWebView(renderer: renderer)

                if !renderer.hasDiagram {
                    if renderer.state == .rendering {
                        ProgressView("Rendering diagram…")
                    } else {
                        ContentUnavailableView(
                            "Diagram Preview", systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text(emptyPreviewMessage)
                        )
                    }
                }

                if renderer.isPreviewStale {
                    Text("Previous preview. Refresh or fix the source to update it.")
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private var emptyPreviewMessage: String {
        if renderer.state.error != nil { return "Fix the source to generate a preview." }
        if !renderer.isLivePreviewEnabled { return "Preview paused. Use Refresh Preview when ready." }
        return "Start typing or choose File > New from Template."
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                zoomControls
                Spacer(minLength: 8)
                themePicker
                liveControls
            }
            VStack(spacing: 6) {
                HStack {
                    zoomControls
                    Spacer()
                    themePicker
                }
                HStack {
                    liveControls
                    Spacer()
                }
            }
        }
        .controlSize(.small)
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                renderer.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")
            .accessibilityLabel("Zoom Out")

            Menu {
                Toggle(
                    "Fit to Window",
                    isOn: Binding(get: { renderer.fitsWindow }, set: { _ in renderer.resetZoom() }))
                Divider()
                ForEach([25, 50, 100, 150, 200, 300, 500], id: \.self) { percent in
                    Button("\(percent)%") { renderer.setZoom(Double(percent) / 100) }
                }
            } label: {
                Text("\(Int((renderer.zoomLevel * 100).rounded()))%")
                    .monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel("Preview zoom, \(Int((renderer.zoomLevel * 100).rounded())) percent")
            .help("100% is actual size. Scroll to pan; pinch or Option-scroll to zoom.")

            Button {
                renderer.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")
            .accessibilityLabel("Zoom In")
        }
    }

    private var themePicker: some View {
        Picker("Theme", selection: $renderer.theme) {
            ForEach(MermaidTheme.allCases, id: \.self) { theme in
                Text(theme.label).tag(theme)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("Diagram Theme")
        .accessibilityLabel("Diagram Theme")
    }

    private var liveControls: some View {
        HStack(spacing: 4) {
            Button {
                renderer.isLivePreviewEnabled.toggle()
            } label: {
                Image(systemName: renderer.isLivePreviewEnabled ? "pause" : "play")
            }
            .help(renderer.isLivePreviewEnabled ? "Pause Live Preview" : "Resume Live Preview")
            .accessibilityLabel(renderer.isLivePreviewEnabled ? "Pause Live Preview" : "Resume Live Preview")

            Button {
                renderer.refreshCurrentSource()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Preview (⌘R)")
            .accessibilityLabel("Refresh Preview")
        }
    }
}

struct MermaidWebView: NSViewRepresentable {
    let renderer: MermaidRenderer

    func makeNSView(context: Context) -> DiagramWebView {
        renderer.webView
    }

    func updateNSView(_ webView: DiagramWebView, context: Context) {}
}
