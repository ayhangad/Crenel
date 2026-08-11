#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
readonly tool_source="${repo_root}/Tools/MeetingNotchCanaryAudit/main.swift"
readonly auditor_source="${repo_root}/MeetingNotch/Services/Audio/PrivacyCanaryFileAuditor.swift"
readonly temporary_directory="$(mktemp -d -t meetingnotch-canary-audit.XXXXXX)"
readonly executable_path="${temporary_directory}/MeetingNotchCanaryAudit"

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
