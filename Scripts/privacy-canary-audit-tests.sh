#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
readonly temporary_directory="$(mktemp -d -t meetingnotch-canary-audit-tests.XXXXXX)"
readonly fixture_executable="${temporary_directory}/fixture"
readonly forbidden_phrase="kehribar pusula yedi kırmızı lale"

cleanup() {
  rm -rf "${temporary_directory}"
}
trap cleanup EXIT INT TERM

xcrun swiftc \
  -O \
  -framework AVFoundation \
  "${repo_root}/Tools/MeetingNotchCanaryAuditFixture/main.swift" \
  -o "${fixture_executable}"

pass_fixture="${temporary_directory}/pass-fixture"
"${fixture_executable}" "${pass_fixture}" 440 "güvenli sentetik toplantı"
"${repo_root}/Scripts/privacy-canary-audit.sh" \
  --report-dir "${temporary_directory}/pass-report" \
  --audio "${pass_fixture}/fixture.m4a" \
  --transcript "${pass_fixture}/transcript.json" \
  --forbidden-phrase "${forbidden_phrase}" \
  --minimum-duration-seconds 0.4 >/dev/null
jq -e '.audio[0].passed == true and .transcripts[0].passed == true' \
  "${temporary_directory}/pass-report/canary-audit.json" >/dev/null
print -r -- "PASS: clean audio/transcript fixture accepted"

set +e
"${repo_root}/Scripts/privacy-canary-audit.sh" \
  --report-dir "${temporary_directory}/invalid-report" \
  --audio "${pass_fixture}/fixture.m4a" \
  --transcript "${pass_fixture}/transcript.json" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" == 2 ]] || {
  print -u2 -- "FAIL: cümlesiz transcript denetimi exit 2 yerine ${invalid_status} döndürdü."
  exit 1
}

fail_fixture="${temporary_directory}/fail-fixture"
"${fixture_executable}" "${fail_fixture}" 997 "${forbidden_phrase}"
set +e
"${repo_root}/Scripts/privacy-canary-audit.sh" \
  --report-dir "${temporary_directory}/fail-report" \
  --audio "${fail_fixture}/fixture.m4a" \
  --transcript "${fail_fixture}/transcript.json" \
  --forbidden-phrase "${forbidden_phrase}" \
  --minimum-duration-seconds 0.4 >/dev/null
fail_status=$?
set -e
[[ "${fail_status}" == 1 ]] || {
  print -u2 -- "FAIL: sızıntı fixture'ı exit 1 yerine ${fail_status} döndürdü."
  exit 1
}
jq -e '.audio[0].passed == false and .transcripts[0].passed == false' \
  "${temporary_directory}/fail-report/canary-audit.json" >/dev/null
print -r -- "PASS: leaking tone/transcript fixture rejected with exit 1"

print -r -- "PASS: privacy canary CLI pass/fail evidence"
