import AppKit
import SwiftUI
import WebKit

private enum Constants {
    static let zoomButtonSpacing: CGFloat = 6
    static let zoomLevelMinWidth: CGFloat = 42
    static let themePickerSpacing: CGFloat = 4
    static let toolbarHorizontalPadding: CGFloat = 12
    static let toolbarVerticalPadding: CGFloat = 6
}

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
                            description: Text("Start typing or choose File > New from Template.")
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

    private var toolbar: some View {
        HStack {
            HStack(spacing: Constants.zoomButtonSpacing) {
                Button {
                    renderer.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom Out")
                .accessibilityLabel("Zoom Out")

                Button {
                    renderer.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom In")
                .accessibilityLabel("Zoom In")

                Button {
                    renderer.resetZoom()
                } label: {
                    Text("100%")
                        .font(.caption.monospacedDigit())
                }
                .help("Actual Size")
                .accessibilityLabel("Reset Zoom to Actual Size")

                Text("\(Int((renderer.zoomLevel * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Constants.zoomLevelMinWidth, alignment: .trailing)
                    .accessibilityLabel("Zoom level \(Int((renderer.zoomLevel * 100).rounded())) percent")
            }

            Spacer()

            HStack(spacing: Constants.themePickerSpacing) {
                Text("Theme:")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Picker("Theme", selection: $renderer.theme) {
                    ForEach(MermaidTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("Diagram Theme")
            }
        }
        .padding(.horizontal, Constants.toolbarHorizontalPadding)
        .padding(.vertical, Constants.toolbarVerticalPadding)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MermaidWebView: NSViewRepresentable {
    let renderer: MermaidRenderer

    func makeNSView(context: Context) -> DiagramWebView {
        renderer.webView
    }

    func updateNSView(_ webView: DiagramWebView, context: Context) {}
}
