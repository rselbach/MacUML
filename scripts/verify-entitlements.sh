#!/bin/bash
# Verifies the entitlement policy and a signed app bundle when provided.

set -euo pipefail

readonly APP_NAME="MacUML"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
SOURCE_ENTITLEMENTS_FILE="${PROJECT_ROOT}/Sources/Entitlements.plist"
readonly SOURCE_ENTITLEMENTS_FILE
ENTITLEMENTS_FILE=""

err() {
  echo "ERROR: $*" >&2
  exit 1
}

validate_plist() {
  [[ -f "${ENTITLEMENTS_FILE}" ]] \
    || err "Entitlements file not found: ${ENTITLEMENTS_FILE}"

  plutil -lint "${ENTITLEMENTS_FILE}" >/dev/null \
    || err "Invalid plist: ${ENTITLEMENTS_FILE}"
}

verify_entitlements() {
  ENTITLEMENTS_FILE="$1"
  local description="$2"

  validate_plist

  require_true "com.apple.security.app-sandbox"
  require_true "com.apple.security.network.client"
  require_true "com.apple.security.files.user-selected.read-write"

  require_array_equals "com.apple.security.temporary-exception.mach-lookup.global-name" \
    "com.rselbach.MacUML-spks" \
    "com.rselbach.MacUML-spki"

  require_missing "com.apple.security.cs.allow-jit"
  require_missing "com.apple.security.cs.allow-unsigned-executable-memory"
  require_missing "com.apple.security.cs.disable-library-validation"
  require_missing "com.apple.security.cs.allow-dyld-environment-variables"
  require_missing "com.apple.security.network.server"

  echo "Entitlements check passed (${description})"
}

verify_signed_entitlements() {
  local path="$1"
  local description="$2"
  local entitlements
  local diagnostics

  entitlements="$(mktemp)"
  diagnostics="$(mktemp)"
  if ! codesign -d --entitlements :- "${path}" > "${entitlements}" 2> "${diagnostics}"; then
    cat "${diagnostics}" >&2
    rm -f "${entitlements}"
    rm -f "${diagnostics}"
    err "Failed reading signed entitlements from ${path}"
  fi

  verify_entitlements "${entitlements}" "${description}"
  rm -f "${entitlements}"
  rm -f "${diagnostics}"
}

verify_bundle() {
  local bundle="$1"
  local executable="${bundle}/Contents/MacOS/${APP_NAME}"

  [[ -d "${bundle}" ]] || err "App bundle not found: ${bundle}"
  [[ -f "${executable}" ]] || err "App executable not found: ${executable}"

  codesign --verify --deep --strict --verbose=2 "${bundle}"
  verify_signed_entitlements "${executable}" "signed executable"
  verify_signed_entitlements "${bundle}" "signed app bundle"
}

plist_read() {
  local key="$1"
  local output

  if output=$(/usr/libexec/PlistBuddy -c "Print :${key}" "${ENTITLEMENTS_FILE}" 2>&1); then
    printf '%s\n' "${output}"
    return 0
  fi

  if [[ "${output}" == *"Does Not Exist"* ]]; then
    return 0
  fi

  err "Failed reading entitlement '${key}': ${output}"
}

plist_read_array_index() {
  local key="$1"
  local index="$2"
  local output

  if output=$(/usr/libexec/PlistBuddy -c "Print :${key}:${index}" "${ENTITLEMENTS_FILE}" 2>&1); then
    printf '%s\n' "${output}"
    return 0
  fi

  if [[ "${output}" == *"Does Not Exist"* ]]; then
    return 0
  fi

  err "Failed reading entitlement '${key}:${index}': ${output}"
}

require_true() {
  local key="$1"
  local value

  value="$(plist_read "${key}")"
  [[ "${value}" == "true" ]] \
    || err "Expected entitlement '${key}' to be true, got '${value}'"
}

require_missing() {
  local key="$1"
  local value

  value="$(plist_read "${key}")"
  [[ -z "${value}" ]] \
    || err "Entitlement '${key}' must not be present (found '${value}')"
}

require_array_equals() {
  local key="$1"
  shift
  local expected=("$@")

  local i
  for i in "${!expected[@]}"; do
    local value
    value="$(plist_read_array_index "${key}" "${i}")"
    [[ "${value}" == "${expected[$i]}" ]] \
      || err "Entitlement array '${key}' index ${i}: expected '${expected[$i]}', got '${value}'"
  done

  local extra_index="${#expected[@]}"
  local extra

  extra="$(plist_read_array_index "${key}" "${extra_index}")"
  [[ -z "${extra}" ]] \
    || err "Entitlement array '${key}' has unexpected extra value at index ${extra_index}: '${extra}'"
}

main() {
  case "$#" in
    0)
      verify_entitlements "${SOURCE_ENTITLEMENTS_FILE}" "${SOURCE_ENTITLEMENTS_FILE}"
      ;;
    1)
      verify_entitlements "${SOURCE_ENTITLEMENTS_FILE}" "${SOURCE_ENTITLEMENTS_FILE}"
      verify_bundle "$1"
      ;;
    *)
      err "usage: verify-entitlements.sh [MacUML.app]"
      ;;
  esac
}

main "$@"
