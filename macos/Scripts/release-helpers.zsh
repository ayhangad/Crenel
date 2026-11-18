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

upload_release_assets() {
    local version="$1" dmg="$2" notes="$3" revision="$4" repo="ayhangad/Crenel"
    if ! gh release view "v${version}" --repo "${repo}" >/dev/null; then
        gh release create "v${version}" --repo "${repo}" --target "${revision}" --title "Crenel ${version}" --notes-file "${notes}" || return 1
    fi
    gh release upload "v${version}" "${dmg}" "${dmg}.sha256" --repo "${repo}" --clobber
}
