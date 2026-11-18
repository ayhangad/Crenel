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
