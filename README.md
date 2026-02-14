# MacUML

[![Swift 6.1+](https://img.shields.io/badge/Swift-6.1%2B-orange.svg)](https://swift.org)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/rselbach/MacUML)](https://github.com/rselbach/MacUML/releases/latest)

A native macOS editor for [Mermaid](https://mermaid.js.org/) diagrams with live preview.

![MacUML Screenshot](https://github.com/rselbach/MacUML/blob/main/assets/MacUML.png)

## Features

- Native SwiftUI interface
- Live diagram preview as you type
- Syntax highlighting for Mermaid code
- Document-based app (`.mmd` and `.mermaid` files)
- Automatic updates via Sparkle

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

For release-style local packaging:

```bash
just release-bundle
```

This creates `.build/release-bundle/MacUML.app`.

## Vendored Mermaid JavaScript

MacUML vendors Mermaid at `Sources/Resources/mermaid.min.js`.

- Version: `11.12.2`
- SHA-256: `d0830a6c05546e9edb8fe20a8f545f3e0dc7c4c3134d584bad9c13a99d7a71e0`

See `RELEASING.md` for update and provenance steps.

## Security-sensitive entitlements

MacUML ships sandboxed and keeps entitlements intentionally narrow.

- `com.apple.security.network.client`: required for Sparkle update checks/downloads
- `com.apple.security.files.user-selected.read-write`: user-opened/saved files
- Sparkle mach-lookup temporary exceptions for updater helper services

Policy is enforced by `scripts/verify-entitlements.sh` in CI.

## License

[MIT](LICENSE)
