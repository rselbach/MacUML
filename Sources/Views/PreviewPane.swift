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

                case .rendering, .ready, .failure:
                    MermaidWebView(renderer: renderer)
                }
            }
            .contextMenu {
                Button("Copy as PNG") {
                    Task {
                        await copyAsPNG()
                    }
                }
                .disabled(renderer.state != .ready)

                Button("Copy as SVG") {
                    Task {
                        await copyAsSVG()
                    }
                }
                .disabled(renderer.state != .ready)
            }
        }
    }
    
    private var toolbar: some View {
        HStack {
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
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func copyAsPNG() async {
        guard let pngData = await renderer.copyAsPNG() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    private func copyAsSVG() async {
        guard let svg = await renderer.copySVG() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(svg, forType: .string)
    }
}

struct MermaidWebView: NSViewRepresentable {
    let renderer: MermaidRenderer

    func makeNSView(context: Context) -> WKWebView {
        renderer.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
    }
}
