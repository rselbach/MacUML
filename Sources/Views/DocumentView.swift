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
    static let largeFileLineThreshold: Int = 5000
}

struct DocumentView: View {
    @Binding var document: MermaidDocument
    @StateObject private var renderer = MermaidRenderer()

    @State private var errorLine: Int?
    @State private var showLargeFileWarning = false
    @State private var cachedLineCount: Int = 0

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                EditorView(text: $document.text, lineCount: $cachedLineCount, errorLine: errorLine)

                if let error = renderer.state.error {
                    ErrorBar(error: error)
                } else if showLargeFileWarning {
                    LargeFileWarningBar(lineCount: cachedLineCount)
                }
            }
            .frame(minWidth: Constants.editorMinWidth)

            PreviewPane(renderer: renderer)
                .frame(minWidth: Constants.previewMinWidth)
        }
        .frame(minWidth: Constants.windowMinWidth, minHeight: Constants.windowMinHeight)
        .focusedValue(\.renderer, renderer)
        .focusedValue(\.formatDocument) { [document = $document] in
            let formatted = MermaidFormatter.format(document.wrappedValue.text)
            if formatted != document.wrappedValue.text {
                document.wrappedValue.text = formatted
            }
        }
        .onChange(of: document.text) { _, newValue in
            renderer.render(source: newValue)
            updateLargeFileWarning()
        }
        .onChange(of: renderer.state.error) { _, newError in
            errorLine = newError?.line
        }
        .onAppear {
            renderer.render(source: document.text)
            updateLargeFileWarning()
        }
    }

    private func updateLargeFileWarning() {
        showLargeFileWarning = cachedLineCount >= Constants.largeFileLineThreshold
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

private struct LargeFileWarningBar: View {
    let lineCount: Int

    var body: some View {
        HStack(spacing: Constants.errorBarSpacing) {
            Image(systemName: "speedometer")
                .foregroundStyle(.white)

            Text("Large file (\(lineCount.formatted()) lines) — editing may be slower")
                .lineLimit(1)

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, Constants.errorBarHorizontalPadding)
        .padding(.vertical, Constants.errorBarVerticalPadding)
        .background(Color.orange.opacity(Constants.errorBarBackgroundOpacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Large file performance warning")
    }
}
