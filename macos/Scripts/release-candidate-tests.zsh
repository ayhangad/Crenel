#!/bin/zsh
set -euo pipefail
source "${0:A:h}/release-helpers.zsh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "${fixture}"' EXIT
root="${fixture:A}/project"
mkdir -p "${root}/artifacts/release" "${fixture}/elsewhere"
for version in 1.0 10.12.2; do
    [[ "$(checked_artifact_directory "${root}" "${version}")" == "${root}/artifacts/release/${version}" ]]
done
for version in '' 1 1.2.3.4 '1x2' '1.0-beta' '../1.0'; do
    if checked_artifact_directory "${root}" "${version}" >/dev/null; then exit 1; fi
done
ln -s "${fixture}/elsewhere" "${root}/artifacts/release/1.0"
if checked_artifact_directory "${root}" 1.0 >/dev/null; then exit 1; fi
mv "${root}/artifacts/release" "${root}/artifacts/other"
ln -s "${fixture}/elsewhere" "${root}/artifacts/release"
if checked_artifact_directory "${root}" 1.0 >/dev/null; then exit 1; fi
print 'Release path checks passed.'

print -rn 'abc' > "${fixture}/archive"
digest=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
verify_sparkle_archive "${fixture}/archive" "${digest}"
print -n 'd' >> "${fixture}/archive"
if verify_sparkle_archive "${fixture}/archive" "${digest}"; then exit 1; fi

# The first upload fails after creation. The next run reuses the release.
gh() {
    case "$2" in
        view) [[ -f "${fixture}/release" ]] ;;
        create) [[ ! -f "${fixture}/release" ]] && touch "${fixture}/release" ;;
        upload)
            [[ "${@[-1]}" == --clobber ]] || return 1
            [[ -f "${fixture}/allow-upload" ]] ;;
        *) return 1 ;;
    esac
}
if upload_release_assets 1.0 example.dmg notes.md revision; then exit 1; fi
touch "${fixture}/allow-upload"
upload_release_assets 1.0 example.dmg notes.md revision
print 'Sparkle integrity and resumable publication checks passed.'
