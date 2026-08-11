#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
readonly auditor_source="${repo_root}/MeetingNotch/Services/Meeting/MeetingSessionAcceptanceAudit.swift"
readonly tool_source="${repo_root}/Tools/MeetingNotchSessionAudit/main.swift"
readonly temporary_directory="$(mktemp -d -t meetingnotch-session-audit.XXXXXX)"
readonly executable_path="${temporary_directory}/MeetingNotchSessionAudit"

cleanup() {
  rm -rf "${temporary_directory}"
}
trap cleanup EXIT INT TERM

xcrun swiftc -O "${auditor_source}" "${tool_source}" -o "${executable_path}"
"${executable_path}" "$@"
