# MacUML

[![Swift 6.1+](https://img.shields.io/badge/Swift-6.1%2B-orange.svg)](https://swift.org)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/rselbach/MacUML)](https://github.com/rselbach/MacUML/releases/latest)

A native macOS editor for [Mermaid](https://mermaid.js.org/) diagrams with live preview.

![MacUML Screenshot](https://github.com/rselbach/MacUML/blob/main/assets/MacUML.png)

## Features

- Native SwiftUI interface
- Live diagram preview with pause and manual refresh
- Syntax highlighting for Mermaid code
- Document-based app (`.mmd` and `.mermaid` files)
- Flowchart, sequence, class, state, and blank templates
- Per-document themes saved in Mermaid front matter
- SVG and PNG file export and clipboard copy
- Editor, split, and preview layouts with a saved divider position
- Error details and navigation to the affected source line
- Local Mermaid syntax help
- Automatic updates via Sparkle in release builds

## Using MacUML

Choose **File > New from Template** to start a diagram, then edit its Mermaid
source. **Help > Mermaid Syntax Help** includes short examples and keyboard
commands. Mermaid diagrams are text files, so they work with version control and
other Mermaid tools.

Use the toolbar's **Export** menu to save or copy the complete diagram as SVG or
PNG. Export does not depend on the preview's zoom or pan position. Exports use
the theme's background color so dark diagrams stay readable; choose Transparent
under **Settings > Export** to omit it. PNG exports default to 2× resolution;
the same settings section offers 1× and 3×. When an edit
contains an error, the last successful preview stays visible with a notice.
Export becomes available again once the preview matches the source.

Scroll to pan the preview. Pinch, or hold Option while scrolling, to zoom. **Fit to
Window** shrinks large diagrams to the window and shows small ones at actual size,
and it keeps fitting as you edit until you zoom. The displayed percentage is the
diagram's actual scale.
Pause Live Preview while making a series of edits to a large file, then use
Refresh Preview when ready.

The preview's theme menu saves the choice in the document as Mermaid front
matter (`config.theme`), so the file and other Mermaid tools keep it. **App
Default** removes it and uses the theme chosen in Settings.

| Command | Shortcut |
| --- | --- |
| Editor / Split / Preview | ⌘1 / ⌘2 / ⌘3 |
| Refresh Preview | ⌘R |
| Fit to Window | ⌘0 |
| Export PNG | ⌘⇧E |
| Copy SVG | ⌘⇧C |
| Format Document | ⌘⇧F |
| Mermaid Syntax Help | ⌘/ |

Format Document cleans up whitespace and preserves Mermaid syntax. The optional
formatting setting in Settings applies to explicit Save and Save As commands.
Autosave preserves in-progress typing. Formatting can be undone.

## Installation

Download the latest DMG from [Releases](https://github.com/rselbach/MacUML/releases/latest), open it, and drag MacUML to your Applications folder.

## Building and Running from Source

### Requirements

- macOS 15.0+
- Swift 6.1+ toolchain (Xcode 16.3 or newer)
- [`just`](https://github.com/casey/just)

### Common tasks

```bash
just build
just test
just verify-security
just bundle
just run
```

- `just bundle` creates `.build/debug-bundle/MacUML.app`
- `just run` opens `.build/debug-bundle/MacUML.app`

Local bundles use the production sandbox entitlements and verify the final app's
signature and entitlements. Debug builds disable Sparkle update checks.

For release-style local packaging:

```bash
just release-bundle
```

This creates `.build/release-bundle/MacUML.app`.

## Vendored Mermaid JavaScript

MacUML vendors Mermaid at `Sources/Resources/mermaid.min.js`.

- Version: `11.12.2`
- SHA-256: `d0830a6c05546e9edb8fe20a8f545f3e0dc7c4c3134d584bad9c13a99d7a71e0`

See [Releasing MacUML](docs/RELEASING.md) for update and provenance steps.

## Security-sensitive entitlements

MacUML ships sandboxed and keeps entitlements intentionally narrow.

- `com.apple.security.network.client`: required for Sparkle update checks/downloads
- `com.apple.security.files.user-selected.read-write`: user-opened/saved files
- Sparkle mach-lookup temporary exceptions for updater helper services

Policy is enforced by `scripts/verify-entitlements.sh` in CI and checked against
the signed app during bundling.

## License

[MIT](LICENSE)
