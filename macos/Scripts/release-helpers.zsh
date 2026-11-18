# Shared by release-candidate.sh and its offline regression tests.
release_version_is_valid() {
    local pattern='^[0-9]+(\.[0-9]+){1,2}$'
    [[ "$1" =~ ${pattern} ]]
}

checked_artifact_directory() {
    local project_root="${1:A}" version="$2"
    release_version_is_valid "${version}" || return 1
    local base="${project_root}/artifacts/release"
    local candidate="${base}/${version}"
    [[ "${base:A}" == "${base}" && ! -L "${candidate}" && "${candidate:A:h}" == "${base}" ]] || return 1
    print -r -- "${candidate}"
}

verify_sparkle_archive() {
    local archive="$1" expected="$2"
    local result
    result="$(shasum -a 256 < "${archive}")" || return 1
    [[ "${result%% *}" == "${expected}" ]]
}

# A new release stays a draft until its files are uploaded, so a run that stops halfway
# can be resumed. A public release is never given different files: a rerun with the same
# build only continues to the feed, and a different build needs a new version.
upload_release_assets() {
    local version="$1" dmg="$2" notes="$3" revision="$4" repo="ayhangad/Crenel" state published
    if state="$(gh release view "v${version}" --repo "${repo}" --json isDraft --jq .isDraft 2>&1)"; then
        if [[ "${state}" != true ]]; then
            published="$(gh release download "v${version}" --repo "${repo}" --pattern "${dmg:t}.sha256" --output - 2>/dev/null)" || published=""
            [[ -n "${published}" && "${published}" == "$(<"${dmg}.sha256")" ]] && return 0
            print -u2 "v${version} is already public with a different build. Release a new version instead."
            return 1
        fi
    elif [[ "${state}" == *"release not found"* ]]; then
        gh release create "v${version}" --repo "${repo}" --target "${revision}" --title "Crenel ${version}" \
            --notes-file "${notes}" --draft || return 1
    else
        print -u2 "Couldn't check v${version} on GitHub: ${state}"
        return 1
    fi
    # The same DMG under a fixed name, so releases/latest/download/Crenel.dmg (the site's
    # Download button) always fetches the newest version.
    local stable_dir
    stable_dir="$(mktemp -d)" || return 1
    cp "${dmg}" "${stable_dir}/Crenel.dmg" || { rm -rf -- "${stable_dir}"; return 1; }
    gh release upload "v${version}" "${dmg}" "${dmg}.sha256" "${stable_dir}/Crenel.dmg" --repo "${repo}" --clobber \
        || { rm -rf -- "${stable_dir}"; return 1; }
    rm -rf -- "${stable_dir}"
    gh release edit "v${version}" --repo "${repo}" --draft=false
}
