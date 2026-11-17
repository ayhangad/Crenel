#!/bin/zsh

set -euo pipefail

readonly OPT_IN_SENTINEL="/tmp/Crenel.run-audio-integration-tests"

cleanup() {
  rm -f "$OPT_IN_SENTINEL"
}

trap cleanup EXIT INT TERM
touch "$OPT_IN_SENTINEL"

xcodebuild test \
  -project Crenel.xcodeproj \
  -scheme Crenel \
  -destination 'platform=macOS' \
  -only-testing:CrenelTests/MicrophoneCaptureIntegrationTests \
  -only-testing:CrenelTests/SystemAudioCaptureIntegrationTests
