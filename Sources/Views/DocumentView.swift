import SwiftUI
import AppKit

private enum Constants {
    static let editorMinWidth: CGFloat = 300
    static let previewMinWidth: CGFloat = 300
    static let windowMinWidth: CGFloat = 700
    static let windowMinHeight: CGFloat = 500
    static let errorBarSpacing: CGFloat = 6
    static let errorBarHorizontalPadding: CGFloat = 8
    static let errorBarVerticalPadding: CGFloat = 4
    static let errorBarBackgroundOpacity: Double = 0.85
}

struct DocumentView: View {
    @Binding var document: MermaidDocument
    @StateObject private var renderer = MermaidRenderer()

    // Derived state to prevent unnecessary editor re-renders
    @State private var errorLine: Int?
    @State private var errorMessage: String?
    @State private var hasError = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                EditorView(text: $document.text, errorLine: errorLine)

                if hasError, let message = errorMessage, let error = renderer.state.error {
                    ErrorBar(error: error)
                }
            }
            .frame(minWidth: Constants.editorMinWidth)

            PreviewPane(renderer: renderer)
                .frame(minWidth: Constants.previewMinWidth)
        }
        .frame(minWidth: Constants.windowMinWidth, minHeight: Constants.windowMinHeight)
        .focusedValue(\.renderer, renderer)
        .onChange(of: document.text) { _, newValue in
            renderer.render(source: newValue)
        }
        .onChange(of: renderer.state.error) { _, newError in
            // Only update editor-affecting state when error actually changes
            let newLine = newError?.line
            let newMessage = newError?.message
            if errorLine != newLine { errorLine = newLine }
            if errorMessage != newMessage { errorMessage = newMessage }
            hasError = newError != nil
        }
        .onAppear {
            renderer.render(source: document.text)
        }
    }
}

private struct ErrorBar: View {
    let error: MermaidError

    var body: some View {
        HStack(spacing: Constants.errorBarSpacing) {
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
            .accessibilityLabel("Copy Error Message")
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, Constants.errorBarHorizontalPadding)
        .padding(.vertical, Constants.errorBarVerticalPadding)
        .background(Color.red.opacity(Constants.errorBarBackgroundOpacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diagram Error")
    }
}