#!/bin/bash
# Assembles MacUML.app bundle from SwiftPM build output.
# Mirrors the CI release workflow (.github/workflows/release.yml).
#
# Usage: bundle-app.sh [debug|release]
#   Defaults to debug if no argument given.

set -euo pipefail

readonly APP_NAME="MacUML"

# --- helpers ---------------------------------------------------------------

err() {
  echo "ERROR: $*" >&2
  exit 1
}

detect_arch() {
  uname -m
}

swift_bin_path() {
  local config="$1"
  swift build -c "${config}" --show-bin-path
}

find_sparkle() {
  local bin_path="$1" arch="$2" config="$3"

  local candidates=(
    "${bin_path}/Sparkle.framework"
    "$(dirname "${bin_path}")/Sparkle.framework"
    "${PROJECT_ROOT}/.build/${arch}-apple-macosx/${config}/Sparkle.framework"
    "${PROJECT_ROOT}/.build/artifacts/sparkle/Sparkle/Sparkle.framework"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "${candidate}" ]]; then
      echo "${candidate}"
      return
    fi
  done

  err "Sparkle.framework not found; run 'swift build -c ${config}' first"
}

sign_bundle() {
  local bundle="$1"
  local contents="${bundle}/Contents"
  local framework="${contents}/Frameworks/Sparkle.framework"
  local executable="${contents}/MacOS/${APP_NAME}"
  local identity="-"

  [[ -d "${framework}" ]] || err "missing Sparkle.framework at ${framework}"
  [[ -f "${executable}" ]] || err "missing executable at ${executable}"

  # Signing order matters for nested app bundles/frameworks.
  codesign --force --deep --sign "${identity}" --timestamp=none "${framework}"
  codesign --force --sign "${identity}" --timestamp=none "${executable}"
  codesign --force --sign "${identity}" --timestamp=none "${bundle}"
}

create_bundle() {
  local config="$1"
  local arch
  arch="$(detect_arch)"

  local bin_path
  bin_path="$(swift_bin_path "${config}")"

  local executable="${bin_path}/${APP_NAME}"
  local bundle="${PROJECT_ROOT}/.build/${config}-bundle/${APP_NAME}.app"
  local contents="${bundle}/Contents"

  [[ -f "${executable}" ]] \
    || err "executable not found at ${executable}; run 'swift build -c ${config}' first"

  rm -rf "${bundle}"
  mkdir -p "${contents}/MacOS" \
           "${contents}/Resources" \
           "${contents}/Frameworks"

  cp "${executable}" "${contents}/MacOS/${APP_NAME}"
  cp "${PROJECT_ROOT}/Sources/Info.plist" "${contents}/Info.plist"
  cp "${PROJECT_ROOT}/Sources/Resources/AppIcon.icns" \
     "${contents}/Resources/AppIcon.icns"
  cp "${PROJECT_ROOT}/Sources/Resources/mermaid.min.js" \
     "${contents}/Resources/mermaid.min.js"
  cp "${PROJECT_ROOT}/Sources/Resources/preview.html" \
     "${contents}/Resources/preview.html"
  cp "${PROJECT_ROOT}/Sources/Resources/preview.js" \
     "${contents}/Resources/preview.js"
  cp "${PROJECT_ROOT}/Sources/Resources/preview.css" \
     "${contents}/Resources/preview.css"
  cp "${PROJECT_ROOT}/Sources/Resources/DefaultDiagram.mmd" \
     "${contents}/Resources/DefaultDiagram.mmd"

  local sparkle
  sparkle="$(find_sparkle "${bin_path}" "${arch}" "${config}")"
  cp -R "${sparkle}" "${contents}/Frameworks/"

  install_name_tool -add_rpath \
    @executable_path/../Frameworks \
    "${contents}/MacOS/${APP_NAME}"

  printf 'APPL????' > "${contents}/PkgInfo"
  sign_bundle "${bundle}"

  echo "Built: ${bundle}"
}

# --- main ------------------------------------------------------------------

main() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  PROJECT_ROOT="$(dirname "${script_dir}")"
  readonly PROJECT_ROOT

  local config="${1:-debug}"
  case "${config}" in
    debug|release) ;;
    *) err "unknown config '${config}'; use 'debug' or 'release'" ;;
  esac

  create_bundle "${config}"
}

main "$@"
