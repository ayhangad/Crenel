#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
artifact_root="${repo_root}/artifacts/release"
archive_path="${artifact_root}/Crenel.xcarchive"
export_path="${artifact_root}/export"
zip_path="${artifact_root}/Crenel.zip"
notary_profile="${CRENEL_NOTARY_PROFILE:-Crenel-Notary}"

cd "${repo_root}"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "BLOCKED: xcodegen bulunamadı."
    exit 2
fi

developer_id_line="$(security find-identity -v -p codesigning \
    | grep 'Developer ID Application:' \
    | head -1 \
    || true)"
if [[ -z "${developer_id_line}" ]]; then
    print -u2 "BLOCKED: Keychain'de Developer ID Application sertifikası yok."
    exit 2
fi
developer_id_identity="${developer_id_line#*\"}"
developer_id_identity="${developer_id_identity%\"*}"

if ! xcrun notarytool history --keychain-profile "${notary_profile}" >/dev/null 2>&1; then
    print -u2 "BLOCKED: notarytool profili bulunamadı veya geçersiz: ${notary_profile}"
    exit 2
fi

mkdir -p "${artifact_root}"
rm -rf "${archive_path}" "${export_path}" "${zip_path}"

print "Xcode projesi üretiliyor..."
xcodegen generate

print "Regresyon testleri çalışıyor..."
xcodebuild test \
    -project Crenel.xcodeproj \
    -scheme Crenel \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO

print "Developer ID archive oluşturuluyor..."
xcodebuild archive \
    -project Crenel.xcodeproj \
    -scheme Crenel \
    -configuration Release \
    -archivePath "${archive_path}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${developer_id_identity}" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

print "Archive export ediliyor..."
xcodebuild -exportArchive \
    -archivePath "${archive_path}" \
    -exportPath "${export_path}" \
    -exportOptionsPlist QA/ExportOptions.plist

app_path="${export_path}/Crenel.app"
browser_host_path="${app_path}/Contents/Library/LaunchServices/CrenelBrowserAudioHost"
if [[ ! -x "${browser_host_path}" ]]; then
    print -u2 "FAIL: browser audio native host uygulama paketinde yok."
    exit 1
fi
if [[ -e "${app_path}/Contents/Resources/CrenelBrowserAudioHost" ]]; then
    print -u2 "FAIL: browser audio native host Resources altında yinelenmiş."
    exit 1
fi
codesign --verify --strict --verbose=2 "${browser_host_path}"
codesign -d --verbose=4 "${browser_host_path}" 2>&1 | grep -q 'runtime'
codesign --verify --deep --strict --verbose=2 "${app_path}"
codesign -d --verbose=4 "${app_path}" 2>&1 | grep -q 'runtime'

ditto -c -k --keepParent "${app_path}" "${zip_path}"

print "Notarization gönderiliyor..."
xcrun notarytool submit "${zip_path}" \
    --keychain-profile "${notary_profile}" \
    --wait
xcrun stapler staple "${app_path}"
xcrun stapler validate "${app_path}"
spctl --assess --type execute --verbose=4 "${app_path}"
shasum -a 256 "${zip_path}" > "${zip_path}.sha256"

print "PASS: ${zip_path}"
