#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
readonly extension_root="${repo_root}/BrowserExtension/MeetingNotchChrome"
readonly store_root="${repo_root}/BrowserExtension/ChromeWebStore"
readonly artifact_root="${repo_root}/artifacts/chrome-store"

for command_name in jq magick zip shasum; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    print -u2 -- "FAIL: ${command_name} bulunamadı."
    exit 2
  }
done

mkdir -p "${extension_root}/images" "${store_root}/assets" "${artifact_root}"

for size in 16 32 48 128; do
  magick -background none "${store_root}/Sources/icon.svg" \
    -resize "${size}x${size}" "${extension_root}/images/icon-${size}.png"
done
magick "${store_root}/Sources/icon.svg" \
  -resize 128x128 "${store_root}/assets/store-icon-128.png"
magick "${store_root}/Sources/small-promo.svg" \
  -resize 440x280 "${store_root}/assets/small-promo-440x280.png"

"${repo_root}/Scripts/chrome-extension-tests.sh"

for size in 16 32 48 128; do
  actual="$(magick identify -format '%wx%h' "${extension_root}/images/icon-${size}.png")"
  [[ "${actual}" == "${size}x${size}" ]] || {
    print -u2 -- "FAIL: icon-${size}.png boyutu ${actual}."
    exit 1
  }
done

version="$(jq -r '.version' "${extension_root}/manifest.json")"
[[ "${version}" == <->.<->.<-> ]] || {
  print -u2 -- "FAIL: Geçersiz extension sürümü: ${version}"
  exit 1
}

readonly zip_path="${artifact_root}/MeetingNotch-Chrome-v${version}.zip"
readonly checksum_path="${zip_path}.sha256"
rm -f "${zip_path}" "${checksum_path}"

readonly runtime_files=(
  manifest.json
  background.js
  offscreen.html
  offscreen.js
  pcm-worklet.js
  protocol.js
  popup.html
  popup.css
  popup.js
  images/icon-16.png
  images/icon-32.png
  images/icon-48.png
  images/icon-128.png
)

(
  cd "${extension_root}"
  zip -X -q "${zip_path}" "${runtime_files[@]}"
)

zip_entries="$(unzip -Z1 "${zip_path}")"
grep -qx 'manifest.json' <<< "${zip_entries}"
if grep -Eq '(^|/)(tests|README|package(-lock)?\.json|\.DS_Store)' <<< "${zip_entries}"; then
  print -u2 -- "FAIL: Store ZIP geliştirme dosyası içeriyor."
  exit 1
fi

shasum -a 256 "${zip_path}" > "${checksum_path}"
print -r -- "PASS: ${zip_path}"
