#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
client=""
output_directory=""
window="30m"
required_runs=5

usage() {
  print -r -- "Kullanım: Scripts/session-acceptance-collect.sh --client zoom|googleMeetChrome"
  print -r -- "  --output-dir QA/Evidence/<date>/<case> [--last 30m] [--required-runs 5]"
}

while (( $# > 0 )); do
  case "$1" in
    --client)
      client="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_directory="${2:-}"
      shift 2
      ;;
    --last)
      window="${2:-}"
      shift 2
      ;;
    --required-runs)
      required_runs="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      print -u2 -- "FAIL: bilinmeyen seçenek: $1"
      usage >&2
      exit 2
      ;;
  esac
done

[[ "${client}" == "zoom" || "${client}" == "googleMeetChrome" ]] || {
  print -u2 -- "FAIL: --client zoom veya googleMeetChrome olmalı."
  exit 2
}
[[ -n "${output_directory}" ]] || {
  print -u2 -- "FAIL: --output-dir gerekli."
  exit 2
}
[[ "${window}" =~ ^[1-9][0-9]*[smhd]$ ]] || {
  print -u2 -- "FAIL: --last örneğin 30m veya 2h olmalı."
  exit 2
}
[[ "${required_runs}" =~ ^[1-9][0-9]*$ ]] || {
  print -u2 -- "FAIL: --required-runs pozitif tam sayı olmalı."
  exit 2
}

mkdir -p "${output_directory}"
readonly log_path="${output_directory}/session.ndjson"
/usr/bin/log show \
  --style ndjson \
  --last "${window}" \
  --predicate 'subsystem == "gad.MeetingNotch" AND category == "meeting-session"' \
  > "${log_path}"

{
  print -r -- "# Session evidence environment"
  print -r -- ""
  print -r -- "- Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  print -r -- "- Client: ${client}"
  print -r -- "- Window: ${window}"
  print -r -- "- Required runs: ${required_runs}"
  print -r -- "- Git commit: $(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || print unknown)"
  print -r -- "- Dirty paths: $(git -C "${repo_root}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  print -r -- "- macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  print -r -- "- Hardware model: $(sysctl -n hw.model)"
} > "${output_directory}/environment.md"

"${repo_root}/Scripts/session-acceptance-audit.sh" \
  --input "${log_path}" \
  --client "${client}" \
  --required-runs "${required_runs}" \
  --report-dir "${output_directory}"
