import AppKit
import SwiftUI

struct DocumentView: View {
    @Binding var document: MermaidDocument
    var fileURL: URL? = nil
    @StateObject private var renderer = MermaidRenderer()
    @StateObject private var settings = AppSettings.shared
    @State private var editorActions = EditorActions()
    @State private var cachedLineCount = 0
    @State private var exportError: String?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                EditorView(
                    text: $document.text,
                    lineCount: $cachedLineCount,
                    errorLine: renderer.state.error?.line,
                    editorFont: settings.editorFont,
                    showLineNumbers: settings.showLineNumbers,
                    actions: editorActions
                )
                .frame(minWidth: 280)

                PreviewPane(renderer: renderer)
                    .frame(minWidth: 280)
            }

            if let error = renderer.state.error {
                DiagramErrorView(error: error, goToLine: editorActions.revealLine)
            } else if cachedLineCount >= 5000 {
                HStack {
                    Label("\(cachedLineCount.formatted()) lines", systemImage: "speedometer")
                    Text("Pause the preview to reduce work while editing.")
                    Spacer()
                    Button(renderer.isLivePreviewEnabled ? "Pause Preview" : "Resume Preview") {
                        renderer.isLivePreviewEnabled.toggle()
                    }
                }
                .font(.caption)
                .padding(8)
                .background(.orange.opacity(0.1))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            Menu {
                ExportButtons(actions: exportActions)
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
            }
            .accessibilityLabel("Export Diagram")
            .disabled(!exportActions.isEnabled)
            .help("Export the complete current diagram as SVG or PNG")
            if isExporting {
                ProgressView().controlSize(.small).accessibilityLabel("Exporting diagram")
            }
        }
        .focusedSceneValue(\.renderer, renderer)
        .focusedSceneValue(\.formatDocument, formatDocument)
        .focusedSceneValue(\.exportDiagram, exportActions)
        .onChange(of: document.text) { _, source in
            renderer.render(source: source)
        }
        .onChange(of: renderer.state.error) { _, error in
            guard let error, let window = editorActions.textView?.window else { return }
            let message = error.line.map { "Diagram error on line \($0)" } ?? "Diagram preview unavailable"
            NSAccessibility.post(
                element: window, notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ])
        }
        .onAppear {
            cachedLineCount = Self.lineCount(in: document.text)
            renderer.exportErrorHandler = { [errorState = $exportError] error in
                errorState.wrappedValue = error.localizedDescription
            }
            renderer.render(source: document.text)
        }
        .onDisappear { renderer.exportErrorHandler = nil }
        .alert(
            "Couldn’t Export Diagram",
            isPresented: Binding(
                get: { exportError != nil }, set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var exportActions: DocumentExportActions {
        DocumentExportActions(isEnabled: renderer.canExport && !isExporting, perform: exportDiagram)
    }

    private func exportDiagram(_ action: DiagramExportAction) {
        guard renderer.canExport, !isExporting else { return }
        let presentingWindow = editorActions.textView?.window ?? renderer.webView.window
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                if !action.writesFile {
                    try await renderer.copyDiagram(action.format)
                    return
                }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [action.format.contentType]
                panel.canCreateDirectories = true
                panel.directoryURL = fileURL?.deletingLastPathComponent()
                panel.nameFieldStringValue =
                    (fileURL?.deletingPathExtension().lastPathComponent ?? "Diagram")
                    + "." + action.format.rawValue
                panel.title = action.title
                guard let window = presentingWindow else {
                    exportError = "The document window is no longer available. Reopen the document and try again."
                    return
                }
                guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
                let data = try await renderer.export(action.format)
                try data.write(to: url, options: .atomic)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func formatDocument() {
        let formatted = MermaidFormatter.format(document.text)
        if formatted != document.text {
            document.text = formatted
        }
    }

    nonisolated static func lineCount(in text: String) -> Int {
        var count = 1
        let textLength = text.utf16.count
        var offset = 0
        for char in text.utf16 {
            offset += 1
            if char == 10 && offset < textLength { count += 1 }
        }
        return count
    }
}
