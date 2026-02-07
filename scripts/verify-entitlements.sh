#!/bin/bash
set -euo pipefail

readonly ENTITLEMENTS_FILE="Sources/Entitlements.plist"

err() {
  echo "ERROR: $*" >&2
  exit 1
}

plist_read() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${ENTITLEMENTS_FILE}" 2>/dev/null || true
}

require_true() {
  local key="$1"
  local value
  value="$(plist_read "${key}")"
  [[ "${value}" == "true" ]] || err "Expected entitlement '${key}' to be true, got '${value}'"
}

require_missing() {
  local key="$1"
  local value
  value="$(plist_read "${key}")"
  [[ -z "${value}" ]] || err "Entitlement '${key}' must not be present (found '${value}')"
}

require_array_equals() {
  local key="$1"
  shift
  local expected=("$@")

  local i
  for i in "${!expected[@]}"; do
    local value
    value="$(/usr/libexec/PlistBuddy -c "Print :${key}:${i}" "${ENTITLEMENTS_FILE}" 2>/dev/null || true)"
    [[ "${value}" == "${expected[$i]}" ]] || err "Entitlement array '${key}' index ${i}: expected '${expected[$i]}', got '${value}'"
  done

  local extra_index="${#expected[@]}"
  local extra
  extra="$(/usr/libexec/PlistBuddy -c "Print :${key}:${extra_index}" "${ENTITLEMENTS_FILE}" 2>/dev/null || true)"
  [[ -z "${extra}" ]] || err "Entitlement array '${key}' has unexpected extra value at index ${extra_index}: '${extra}'"
}

require_true "com.apple.security.app-sandbox"
require_true "com.apple.security.network.client"
require_true "com.apple.security.files.user-selected.read-write"

# Sparkle sandbox helper mach services.
require_array_equals "com.apple.security.temporary-exception.mach-lookup.global-name" \
  "com.rselbach.MacUML-spks" \
  "com.rselbach.MacUML-spki"

# High-risk hardened-runtime exceptions should not be present.
require_missing "com.apple.security.cs.allow-jit"
require_missing "com.apple.security.cs.allow-unsigned-executable-memory"
require_missing "com.apple.security.cs.disable-library-validation"
require_missing "com.apple.security.cs.allow-dyld-environment-variables"
require_missing "com.apple.security.network.server"

echo "Entitlements check passed (${ENTITLEMENTS_FILE})"
