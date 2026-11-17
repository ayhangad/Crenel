#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
readonly temporary_directory="$(mktemp -d -t crenel-session-audit-tests.XXXXXX)"

cleanup() {
  rm -rf "${temporary_directory}"
}
trap cleanup EXIT INT TERM

diagnostic() {
  local session_id="$1"
  local state="$2"
  local confidence="$3"
  local client="$4"
  print -r -- "meeting-session-v1 session=${session_id} state=${state} confidence=${confidence} client=${client} microphone=closed evidence=clientUI,process"
}

session_id() {
  printf '00000000-0000-0000-0000-%012d' "$1"
}

pass_log="${temporary_directory}/pass.ndjson"
: > "${pass_log}"
for index in 1 2 3 4 5; do
  id="$(session_id "${index}")"
  message="$(diagnostic "${id}" candidate probable zoom)"
  jq -cn --arg eventMessage "${message}" '{eventMessage: $eventMessage}' >> "${pass_log}"
  diagnostic "${id}" ready confirmed zoom >> "${pass_log}"
  diagnostic "${id}" recording confirmed zoom >> "${pass_log}"
  diagnostic "${id}" endSuspected probable zoom >> "${pass_log}"
  diagnostic "${id}" ended confirmed zoom >> "${pass_log}"
done

"${repo_root}/Scripts/session-acceptance-audit.sh" \
  --input "${pass_log}" \
  --client zoom \
  --required-runs 5 \
  --report-dir "${temporary_directory}/pass-report" >/dev/null
jq -e '.passed == true and .observedRuns == 5 and .passingRuns == 5' \
  "${temporary_directory}/pass-report/session-audit.json" >/dev/null
print -r -- "PASS: five confirmed session lifecycles accepted"

fail_log="${temporary_directory}/fail.ndjson"
cp "${pass_log}" "${fail_log}"
failed_id="$(session_id 5)"
{
  diagnostic "${failed_id}" ended confirmed zoom
  diagnostic "${failed_id}" candidate probable zoom
} >> "${fail_log}"

set +e
"${repo_root}/Scripts/session-acceptance-audit.sh" \
  --input "${fail_log}" \
  --client zoom \
  --required-runs 5 \
  --report-dir "${temporary_directory}/fail-report" >/dev/null
fail_status=$?
set -e
[[ "${fail_status}" == 1 ]] || {
  print -u2 -- "FAIL: terminal regresyon fixture'ı exit 1 yerine ${fail_status} döndürdü."
  exit 1
}
jq -e '.passed == false and .runs[4].terminalStateRegressed == true' \
  "${temporary_directory}/fail-report/session-audit.json" >/dev/null
print -r -- "PASS: terminal regression rejected with exit 1"

print -r -- "PASS: meeting session acceptance CLI evidence"
