#!/bin/zsh

set -euo pipefail

readonly OPT_IN_SENTINEL="/tmp/MeetingNotch.run-audio-integration-tests"

cleanup() {
  rm -f "$OPT_IN_SENTINEL"
}

trap cleanup EXIT INT TERM
touch "$OPT_IN_SENTINEL"

xcodebuild test \
  -project MeetingNotch.xcodeproj \
  -scheme MeetingNotch \
  -destination 'platform=macOS' \
  -only-testing:MeetingNotchTests/MicrophoneCaptureIntegrationTests \
  -only-testing:MeetingNotchTests/SystemAudioCaptureIntegrationTests
