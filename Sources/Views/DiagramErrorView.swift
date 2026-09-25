import AppKit
import SwiftUI

struct DiagramErrorView: View {
    let error: MermaidError
    let goToLine: (Int) -> Void
    @State private var showsDetails = false
    @State private var copyFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(summary, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Spacer()
                if let line = error.line {
                    Button("Go to Line \(line)") { goToLine(line) }
                }
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    copyFailed = !NSPasteboard.general.setString(error.localizedDescription, forType: .string)
                }
            }
            DisclosureGroup("Details", isExpanded: $showsDetails) {
                ScrollView {
                    Text(error.message)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
            }
            .padding(.leading, 16)
        }
        .font(.callout)
        .padding(10)
        .background(.red.opacity(0.08))
        .accessibilityElement(children: .contain)
        .onChange(of: error) { _, _ in showsDetails = false }
        .alert("Couldn’t Copy Details", isPresented: $copyFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The clipboard is unavailable. You can select and copy the text under Details.")
        }
    }

    private var summary: String {
        error.line.map { "Cannot render line \($0)" } ?? "Preview unavailable"
    }
}
