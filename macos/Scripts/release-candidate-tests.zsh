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
