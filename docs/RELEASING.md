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

## Create a release

1. Ensure `main` is green in CI.
2. Create and push a version tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

3. The release workflow builds/signs/notarizes `MacUML-X.Y.Z.dmg`, uploads GitHub Release assets, and deploys `appcast.xml` via GitHub Pages.

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
