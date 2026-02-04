# MacUML

[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/rselbach/MacUML)](https://github.com/rselbach/MacUML/releases/latest)

A native macOS editor for [Mermaid](https://mermaid.js.org/) diagrams with live preview.

![MacUML Screenshot](https://github.com/rselbach/MacUML/assets/placeholder.png)

## Features

- Native SwiftUI interface
- Live diagram preview as you type
- Syntax highlighting for Mermaid code
- Document-based app (`.mmd` and `.mermaid` files)
- Automatic updates via Sparkle

## Installation

Download the latest DMG from [Releases](https://github.com/rselbach/MacUML/releases/latest), open it, and drag MacUML to your Applications folder.

## Building from Source

```bash
swift build -c release
```

The app bundle will be at `.build/release/MacUML`.

## Requirements

- macOS 14.0 (Sonoma) or later

## License

[MIT](LICENSE)
