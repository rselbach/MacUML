#!/bin/bash
# Verifies vendored Mermaid metadata in docs matches the actual JS file hash.

set -euo pipefail

readonly MERMAID_FILE="Sources/Resources/mermaid.min.js"
readonly README_FILE="README.md"
readonly RELEASING_FILE="docs/RELEASING.md"

err() {
  echo "ERROR: $*" >&2
  exit 1
}

extract_version() {
  local file="$1"
  awk -F'`' '/Version: `[^`]+`/ { print $2; exit }' "${file}"
}

extract_sha() {
  local file="$1"
  awk -F'`' '/SHA-256: `[0-9a-f]{64}`/ { print $2; exit }' "${file}"
}

actual_sha="$(shasum -a 256 "${MERMAID_FILE}" | awk '{print $1}')"

readme_version="$(extract_version "${README_FILE}")"
release_version="$(extract_version "${RELEASING_FILE}")"
readme_sha="$(extract_sha "${README_FILE}")"
release_sha="$(extract_sha "${RELEASING_FILE}")"

[[ -n "${readme_version}" ]] || err "Could not find Mermaid version in ${README_FILE}"
[[ -n "${release_version}" ]] || err "Could not find Mermaid version in ${RELEASING_FILE}"
[[ -n "${readme_sha}" ]] || err "Could not find Mermaid SHA-256 in ${README_FILE}"
[[ -n "${release_sha}" ]] || err "Could not find Mermaid SHA-256 in ${RELEASING_FILE}"

[[ "${readme_version}" == "${release_version}" ]] \
  || err "Mermaid version mismatch: README=${readme_version}, docs/RELEASING=${release_version}"

[[ "${readme_sha}" == "${release_sha}" ]] \
  || err "Mermaid SHA mismatch: README=${readme_sha}, docs/RELEASING=${release_sha}"

[[ "${readme_sha}" == "${actual_sha}" ]] \
  || err "Mermaid SHA mismatch with file: docs=${readme_sha}, actual=${actual_sha}"

echo "Mermaid provenance check passed: version=${readme_version}, sha=${actual_sha}"
