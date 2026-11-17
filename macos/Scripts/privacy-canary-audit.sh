#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
readonly tool_source="${repo_root}/Tools/CrenelCanaryAudit/main.swift"
readonly auditor_source="${repo_root}/Crenel/Services/Audio/PrivacyCanaryFileAuditor.swift"
readonly temporary_directory="$(mktemp -d -t crenel-canary-audit.XXXXXX)"
readonly executable_path="${temporary_directory}/CrenelCanaryAudit"

cleanup() {
  rm -rf "${temporary_directory}"
}
trap cleanup EXIT INT TERM

xcrun swiftc \
  -O \
  -framework AVFoundation \
  "${auditor_source}" \
  "${tool_source}" \
  -o "${executable_path}"

"${executable_path}" "$@"
