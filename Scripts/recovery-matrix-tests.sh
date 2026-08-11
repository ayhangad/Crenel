#!/bin/zsh

set -euo pipefail
set -o pipefail

readonly REPO_ROOT="${0:A:h:h}"
readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly ARTIFACT_DIR="${REPO_ROOT}/artifacts/qa/recovery-${RUN_ID}"
readonly LOG_PATH="${ARTIFACT_DIR}/xcodebuild.log"
readonly CANARY_CLI_LOG_PATH="${ARTIFACT_DIR}/canary-cli.log"
readonly SESSION_CLI_LOG_PATH="${ARTIFACT_DIR}/session-cli.log"
readonly RESULT_PATH="${ARTIFACT_DIR}/result.md"

mkdir -p "${ARTIFACT_DIR}"
cd "${REPO_ROOT}"

set +e
xcodebuild test \
  -project MeetingNotch.xcodeproj \
  -scheme MeetingNotch \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MeetingNotchTests/AppStateTests/testSafetyInterruptionAtomicallyWarnsAndMovesRecordingToFinalizing \
  -only-testing:MeetingNotchTests/RecordingCoordinatorTests \
  -only-testing:MeetingNotchTests/RecordingRecoveryServiceTests \
  -only-testing:MeetingNotchTests/ProcessingQueueTests \
  -only-testing:MeetingNotchTests/TranscriptionFoundationTests \
  -only-testing:MeetingNotchTests/TranscriptionProcessingWorkerTests \
  -only-testing:MeetingNotchTests/MicrophoneDeviceTests \
  -only-testing:MeetingNotchTests/MeetingMicrophoneGateTests \
  -only-testing:MeetingNotchTests/SystemAudioCaptureScopeTests \
  -only-testing:MeetingNotchTests/AudioTrackMixerTests \
  -only-testing:MeetingNotchTests/BrowserAudioProtocolTests \
  -only-testing:MeetingNotchTests/BrowserAudioBridgeTests \
  -only-testing:MeetingNotchTests/PrivacyCanaryAuditTests \
  -only-testing:MeetingNotchTests/PrivacyCanaryFileAuditorTests \
  -only-testing:MeetingNotchTests/MeetingSessionAcceptanceAuditTests \
  -only-testing:MeetingNotchTests/PrivacyBoundaryTests \
  2>&1 | tee "${LOG_PATH}"
test_status=$?

"${REPO_ROOT}/Scripts/privacy-canary-audit-tests.sh" \
  2>&1 | tee "${CANARY_CLI_LOG_PATH}"
canary_cli_status=$?
"${REPO_ROOT}/Scripts/session-acceptance-audit-tests.sh" \
  2>&1 | tee "${SESSION_CLI_LOG_PATH}"
session_cli_status=$?
set -e

executed_summary="$(grep -E 'Executed [0-9]+ tests?' "${LOG_PATH}" | tail -1 || true)"
if [[ -z "${executed_summary}" ]]; then
  executed_summary="Test özeti xcodebuild logunda bulunamadı."
fi

if (( test_status == 0 && canary_cli_status == 0 && session_cli_status == 0 )); then
  outcome="PASS"
else
  outcome="FAIL"
fi

{
  print -r -- "# Automated recovery matrix"
  print -r -- ""
  print -r -- "- Run: ${RUN_ID}"
  print -r -- "- Result: ${outcome}"
  print -r -- "- ${executed_summary}"
  print -r -- "- Log: xcodebuild.log"
  print -r -- "- Canary CLI log: canary-cli.log"
  print -r -- "- Session CLI log: session-cli.log"
  print -r -- ""
  print -r -- "Kapsam: disk başlangıç/runtime denetimi, capture recovery, queue restore ve"
  print -r -- "idempotency, transport retry, cihaz/gate kesintisi, system pipeline heartbeat,"
  print -r -- "clock drift, limiter ve sentetik privacy canary."
  print -r -- "Gerçek çıktı auditor'ının temiz fixture'ı geçirdiği ve tone/transcript sızıntısını"
  print -r -- "non-zero sonuçla reddettiği CLI seviyesinde de doğrulanır."
  print -r -- "Beşli confirmed-ready → confirmed-ended session zinciri ve terminal regresyon"
  print -r -- "reddi de privacy-safe log parser/CLI üzerinden doğrulanır."
  print -r -- "Google Meet native mesaj protokolünde origin, framing, sıra ve PCM boyutu da doğrulanır."
} > "${RESULT_PATH}"

print -r -- "${outcome}: ${RESULT_PATH}"
if (( test_status != 0 )); then
  exit "${test_status}"
fi
if (( canary_cli_status != 0 )); then
  exit "${canary_cli_status}"
fi
exit "${session_cli_status}"
