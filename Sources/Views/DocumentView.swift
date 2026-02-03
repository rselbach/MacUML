import SwiftUI

struct DocumentView: View {
    @Binding var document: MermaidDocument
    @StateObject private var renderer = MermaidRenderer()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                EditorView(text: $document.text, errorLine: renderer.currentError?.line)
                
                if let error = renderer.currentError {
                    errorBar(error: error)
                }
            }
            .frame(minWidth: 300)

            PreviewPane(renderer: renderer)
                .frame(minWidth: 300)
        }
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: document.text) { _, newValue in
            renderer.render(source: newValue)
        }
        .onAppear {
            if let theme = MermaidTheme(rawValue: settings.defaultDiagramTheme) {
                renderer.theme = theme
            }
            renderer.render(source: document.text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPreview)) { _ in
            renderer.render(source: document.text, force: true)
        }
        .onChange(of: settings.defaultDiagramTheme) { _, newTheme in
            if let theme = MermaidTheme(rawValue: newTheme) {
                renderer.theme = theme
            }
        }
    }
    
    private func errorBar(error: MermaidError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            
            if let line = error.line {
                Text("Line \(line):")
                    .fontWeight(.medium)
            }
            
            Text(error.message)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.85))
    }
}
