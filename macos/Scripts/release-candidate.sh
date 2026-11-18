#!/bin/zsh
# Builds a Crenel release: tests → Developer ID archive → notarized app → DMG (dmgbuild,
# drawn background) → signed, notarized, stapled DMG → Sparkle appcast entry.
#
#   Scripts/release-candidate.sh 1.0                # signed release candidate
#   Scripts/release-candidate.sh 1.0 --publish      # …and publish: GitHub Release + appcast on gh-pages
#   Scripts/release-candidate.sh 1.0 --unsigned     # local DMG to look at; no signing, no notarization
#
# Needs: xcodegen; for signed builds a "Developer ID Application" identity and the
# notarytool profile (CRENEL_NOTARY_PROFILE, default Crenel-Notary); the Sparkle EdDSA
# key in the login Keychain (account gad.Crenel); for --publish, gh logged in.
# Release notes for the appcast: docs/releases/<version>.md (required with --publish).
# See docs/DISTRIBUTION.md.

set -euo pipefail

source "${0:A:h}/release-helpers.zsh"

version="${1:-}"
shift || true
signed=1
publish=0
for argument in "$@"; do
    case "${argument}" in
        --unsigned) signed=0 ;;
        --publish) publish=1 ;;
        *) print -u2 "Unknown option: ${argument}"; exit 2 ;;
    esac
done
if ! release_version_is_valid "${version}"; then
    print -u2 "usage: release-candidate.sh <version> [--publish | --unsigned]"
    exit 2
fi
if (( publish && !signed )); then
    print -u2 "--publish needs a signed build."
    exit 2
fi

repo_root="${0:A:h:h}"
monorepo_root="${repo_root:h}"
artifact_root="$(checked_artifact_directory "${repo_root}" "${version}")" || { print -u2 "Invalid artifact directory."; exit 2; }
archive_path="${artifact_root}/Crenel.xcarchive"
export_path="${artifact_root}/export"
dmg_work="${artifact_root}/dmg"
updates_dir="${repo_root}/artifacts/release/updates"
dmg_path="${updates_dir}/Crenel-${version}.dmg"
notes_source="${monorepo_root}/docs/releases/${version}.md"
notary_profile="${CRENEL_NOTARY_PROFILE:-Crenel-Notary}"
sparkle_version="2.10.1"
sparkle_tools="${HOME}/.cache/crenel-sparkle-${sparkle_version}"
venv="${HOME}/.cache/crenel-release-venv"
build_number="$(git -C "${monorepo_root}" rev-list --count HEAD)"
feed_url="https://ayhangad.github.io/Crenel/appcast.xml"
download_prefix="https://github.com/ayhangad/Crenel/releases/download/v${version}/"

cd "${repo_root}"

fail() { print -u2 "BLOCKED: $1"; exit 2; }

# MARK: Preflight

command -v xcodegen >/dev/null 2>&1 || fail "xcodegen not found."
if (( signed )); then
    developer_id_line="$(security find-identity -v -p codesigning | grep 'Developer ID Application:' | head -1 || true)"
    [[ -n "${developer_id_line}" ]] || fail "no Developer ID Application identity in the Keychain."
    developer_id_identity="${developer_id_line#*\"}"
    developer_id_identity="${developer_id_identity%\"*}"
    xcrun notarytool history --keychain-profile "${notary_profile}" >/dev/null 2>&1 \
        || fail "notarytool profile missing or invalid: ${notary_profile}"
fi
if (( publish )); then
    [[ -f "${notes_source}" ]] || fail "release notes missing: ${notes_source}"
    gh auth status >/dev/null 2>&1 || fail "gh is not logged in."
    [[ -z "$(git -C "${monorepo_root}" status --porcelain)" ]] || fail "working tree is not clean."
fi

if [[ ! -x "${venv}/bin/dmgbuild" ]]; then
    print "Installing dmgbuild 2.0.0 into ${venv}…"
    python3 -m venv "${venv}"
    "${venv}/bin/pip" install -q "dmgbuild==2.0.0"
fi
if (( signed )) && [[ ! -x "${sparkle_tools}/bin/generate_appcast" ]]; then
    print "Fetching Sparkle ${sparkle_version} tools…"
    mkdir -p "${sparkle_tools}"
    curl -sSL "https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz" \
        | tar -xJ -C "${sparkle_tools}"
fi

[[ "$(checked_artifact_directory "${repo_root}" "${version}")" == "${artifact_root}" ]] || fail "Invalid cleanup target."
rm -rf -- "${artifact_root}"
mkdir -p "${artifact_root}" "${updates_dir}"
rm -f "${dmg_path}"

# MARK: Build

print "Generating the Xcode project…"
xcodegen generate

print "Running tests…"
xcodebuild test -project Crenel.xcodeproj -scheme Crenel -destination 'platform=macOS' \
    -derivedDataPath "${artifact_root}/dd-test" CODE_SIGNING_ALLOWED=NO -quiet

if (( signed )); then
    print "Archiving Crenel ${version} (${build_number}) with Developer ID…"
    xcodebuild archive -project Crenel.xcodeproj -scheme Crenel -configuration Release \
        -archivePath "${archive_path}" -derivedDataPath "${artifact_root}/dd" \
        MARKETING_VERSION="${version}" CURRENT_PROJECT_VERSION="${build_number}" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${developer_id_identity}" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" -quiet
    xcodebuild -exportArchive -archivePath "${archive_path}" -exportPath "${export_path}" \
        -exportOptionsPlist QA/ExportOptions.plist -quiet
else
    print "Building an unsigned Release of Crenel ${version} (${build_number})…"
    xcodebuild build -project Crenel.xcodeproj -scheme Crenel -configuration Release \
        -derivedDataPath "${artifact_root}/dd" \
        MARKETING_VERSION="${version}" CURRENT_PROJECT_VERSION="${build_number}" \
        CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -quiet
    mkdir -p "${export_path}"
    ditto "${artifact_root}/dd/Build/Products/Release/Crenel.app" "${export_path}/Crenel.app"
fi

app_path="${export_path}/Crenel.app"
browser_host_path="${app_path}/Contents/Library/LaunchServices/CrenelBrowserAudioHost"
[[ -x "${browser_host_path}" ]] || { print -u2 "FAIL: browser audio native host is missing from the app."; exit 1; }
[[ -d "${app_path}/Contents/Frameworks/Sparkle.framework" ]] || { print -u2 "FAIL: Sparkle.framework is missing."; exit 1; }

if (( signed )); then
    codesign --verify --deep --strict --verbose=2 "${app_path}"
    # Read it whole first: grep -q stops early and, under pipefail, codesign's broken pipe fails the check.
    signature_details="$(codesign -d --verbose=4 "${app_path}" 2>&1)"
    [[ "${signature_details}" == *"(runtime)"* ]] || { print -u2 "FAIL: hardened runtime is off."; exit 1; }

    print "Notarizing the app…"
    ditto -c -k --keepParent "${app_path}" "${artifact_root}/Crenel-app.zip"
    xcrun notarytool submit "${artifact_root}/Crenel-app.zip" --keychain-profile "${notary_profile}" --wait
    # Staple before the app goes into the compressed DMG; it cannot be stapled there.
    xcrun stapler staple "${app_path}"
    xcrun stapler validate "${app_path}"
    spctl --assess --type execute --verbose=4 "${app_path}"
fi

# MARK: DMG

print "Drawing the DMG background…"
swift "${repo_root}/Scripts/dmg/background.swift" "${dmg_work}" "${version}" "${repo_root}/Crenel/Resources/Fonts"

print "Building the DMG…"
"${venv}/bin/dmgbuild" -s "${repo_root}/Scripts/dmg/settings.py" \
    -D app="${app_path}" -D background="${dmg_work}/background.png" \
    "Crenel" "${dmg_path}"

if (( signed )); then
    print "Signing and notarizing the DMG…"
    codesign --sign "${developer_id_identity}" --timestamp "${dmg_path}"
    xcrun notarytool submit "${dmg_path}" --keychain-profile "${notary_profile}" --wait
    xcrun stapler staple "${dmg_path}"
    xcrun stapler validate "${dmg_path}"
    spctl --assess --type open --context context:primary-signature --verbose=4 "${dmg_path}"
fi
# The checksum comes after stapling, which changes the file.
(cd "${updates_dir}" && shasum -a 256 "${dmg_path:t}" > "${dmg_path:t}.sha256")

if (( !signed )); then
    print "PASS (unsigned, not for distribution): ${dmg_path}"
    exit 0
fi

# MARK: Appcast

print "Updating the appcast…"
if [[ ! -f "${updates_dir}/appcast.xml" ]]; then
    # Keep earlier versions: start from the published feed when there is one.
    curl -sfL "${feed_url}" -o "${updates_dir}/appcast.xml" || rm -f "${updates_dir}/appcast.xml"
fi
[[ -f "${notes_source}" ]] && cp "${notes_source}" "${updates_dir}/Crenel-${version}.md"
"${sparkle_tools}/bin/generate_appcast" --account gad.Crenel \
    --download-url-prefix "${download_prefix}" \
    --embed-release-notes \
    --maximum-deltas 0 \
    "${updates_dir}"
grep -q "sparkle:shortVersionString>${version}<" "${updates_dir}/appcast.xml" \
    || grep -q "sparkle:shortVersionString=\"${version}\"" "${updates_dir}/appcast.xml" \
    || { print -u2 "FAIL: ${version} is not in the appcast."; exit 1; }

if (( !publish )); then
    print "PASS: ${dmg_path}"
    print "      appcast: ${updates_dir}/appcast.xml (run again with --publish to release)"
    exit 0
fi

# MARK: Publish

print "Publishing v${version} on GitHub…"
gh release create "v${version}" "${dmg_path}" "${dmg_path}.sha256" \
    --repo ayhangad/Crenel --title "Crenel ${version}" --notes-file "${notes_source}"

pages="${artifact_root}/gh-pages"
if git -C "${monorepo_root}" ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
    git -C "${monorepo_root}" worktree add -f "${pages}" origin/gh-pages
    git -C "${pages}" switch -C gh-pages
else
    git -C "${monorepo_root}" worktree add -f --orphan -b gh-pages "${pages}"
fi
cp "${updates_dir}/appcast.xml" "${pages}/appcast.xml"
touch "${pages}/.nojekyll"
git -C "${pages}" add appcast.xml .nojekyll
git -C "${pages}" commit -m "Appcast: Crenel ${version}"
git -C "${pages}" push origin gh-pages
git -C "${monorepo_root}" worktree remove "${pages}"

print "PASS: Crenel ${version} released."
print "      ${download_prefix}Crenel-${version}.dmg"
