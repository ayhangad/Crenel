#!/bin/zsh

set -euo pipefail

readonly REPO_ROOT="${0:A:h:h}"
readonly EXTENSION_ROOT="${REPO_ROOT}/chrome"

command -v jq >/dev/null 2>&1 || {
  print -u2 -- "FAIL: jq bulunamadı."
  exit 2
}
command -v node >/dev/null 2>&1 || {
  print -u2 -- "FAIL: Node.js bulunamadı."
  exit 2
}

cd "${EXTENSION_ROOT}"
jq empty manifest.json
node --check background.js
node --check offscreen.js
node --check pcm-worklet.js
node --check popup.js
node --check protocol.js
npm test

print -r -- "PASS: Crenel Chrome extension static and protocol validation"
