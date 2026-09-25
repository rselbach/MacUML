# Releasing MacUML

This repo ships releases through `.github/workflows/release.yml`.

## Prerequisites

Repository secrets required by the workflow:

- `DEVELOPER_ID_CERTIFICATE_P12`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`
- `SPARKLE_EDDSA_PRIVATE_KEY`
- `DEEPSEEK_API_KEY`

## Create a release

1. Ensure `main` is green in CI.
2. Run the tests and build the sandboxed app:

   ```bash
   just test
   just verify-security
   just bundle
   ```

3. Complete the smoke test below.
4. Create and push a version tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

5. The release workflow builds/signs/notarizes `MacUML-X.Y.Z.dmg`, generates release notes from the tag history, uploads GitHub Release assets, and deploys `appcast.xml` via GitHub Pages.

## Sandboxed app smoke test

The bundle script signs the local app with the production entitlements, verifies
its signature, and checks the entitlements on the signed executable. Debug builds
disable production update checks.

1. Launch `.build/debug-bundle/MacUML.app`. Open a UTF-8 Mermaid file from outside
   the app container. Edit, save, close, and reopen it.
2. Enable formatting on Save. Check both Save and Save As, confirm the editor and
   saved file agree, and undo the formatting. Restore the setting afterward.
3. Create flowchart, class, sequence, and state diagrams from templates. Check
   Unicode labels and a label containing `Syntax error`.
4. Introduce an error after leading blank lines. Confirm the reported line, Go to
   Line, expandable details, last successful preview notice, and disabled export.
   Clear the source and change the theme. The old diagram must stay cleared.
5. Export SVG and PNG through the toolbar and copy them through the File menu.
   Reopen both formats. Confirm labels, colors, arrows, and the complete diagram.
   Repeat after zooming and panning; the exported content should be unchanged.
6. Switch pane layouts while editing. Check selection, scrolling, focus, Undo,
   and divider persistence. Change one window's layout with two documents open.
7. Pause the preview, edit, and refresh manually. Resume live preview and confirm
   subsequent edits update it. Check the large-file pause control.
8. Check the minimum window size, larger editor fonts, keyboard access, and
   VoiceOver reading order and error announcements.

Before distribution, also check the notarized release on the minimum supported
macOS version and supported architectures, including an actual Sparkle update.
Local signing does not establish notarization or update behavior.

## Manual workflow dispatch

You can run Release manually via `workflow_dispatch` and pass `version`.

## Vendored Mermaid JS provenance

Vendored file: `Sources/Resources/mermaid.min.js`

- Version: `11.12.2`
- SHA-256: `d0830a6c05546e9edb8fe20a8f545f3e0dc7c4c3134d584bad9c13a99d7a71e0`

### Update process

1. Download a pinned version:

   ```bash
   curl -fsSL "https://cdn.jsdelivr.net/npm/mermaid@<VERSION>/dist/mermaid.min.js" -o Sources/Resources/mermaid.min.js
   ```

2. Compute checksum:

   ```bash
   shasum -a 256 Sources/Resources/mermaid.min.js
   ```

3. Update this file with the new version and checksum.
4. In the same PR, include source URL, version, and resulting checksum.
