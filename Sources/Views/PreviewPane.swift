import SwiftUI
import WebKit
import AppKit

struct PreviewPane: View {
    @ObservedObject var renderer: MermaidRenderer

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            
            ZStack {
                Color(nsColor: .textBackgroundColor)

                switch renderer.state {
                case .idle:
                    Text("Type Mermaid syntax to see preview")
                        .foregroundStyle(.secondary)

                case .rendering, .ready:
                    MermaidWebView(renderer: renderer)

                case .failure(let message, _):
                    MermaidWebView(renderer: renderer)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }
    
    private var toolbar: some View {
        HStack {
            HStack(spacing: 6) {
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
                    .frame(minWidth: 42, alignment: .trailing)
                    .accessibilityLabel("Zoom level \(Int((renderer.zoomLevel * 100).rounded())) percent")
            }

            Spacer()
            
            HStack(spacing: 4) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
