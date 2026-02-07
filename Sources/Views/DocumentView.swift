import SwiftUI
import AppKit

struct DocumentView: View {
    @Binding var document: MermaidDocument
    @StateObject private var renderer = MermaidRenderer()

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
            renderer.render(source: document.text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPreview)) { _ in
            renderer.render(source: document.text, force: true)
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
                .lineLimit(3)
                .truncationMode(.tail)
            
            Spacer()

            Button("Copy") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()

                if let line = error.line {
                    pasteboard.setString("Line \(line): \(error.message)", forType: .string)
                    return
                }

                pasteboard.setString(error.message, forType: .string)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.9))
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.85))
    }
}
