import SwiftUI
import WebKit
import AppKit

private enum Constants {
    static let zoomButtonSpacing: CGFloat = 6
    static let zoomLevelMinWidth: CGFloat = 42
    static let themePickerSpacing: CGFloat = 4
    static let toolbarHorizontalPadding: CGFloat = 12
    static let toolbarVerticalPadding: CGFloat = 6
    static let errorMessageHorizontalPadding: CGFloat = 10
    static let errorMessageVerticalPadding: CGFloat = 6
    static let errorMessageBackgroundOpacity: Double = 0.9
    static let errorMessageOuterPadding: CGFloat = 12
    static let errorMessageCornerRadius: CGFloat = 6
}

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

                case .failure(error: let error):
                    MermaidWebView(renderer: renderer)
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Constants.errorMessageHorizontalPadding)
                        .padding(.vertical, Constants.errorMessageVerticalPadding)
                        .background(Color.red.opacity(Constants.errorMessageBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: Constants.errorMessageCornerRadius))
                        .padding(Constants.errorMessageOuterPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
