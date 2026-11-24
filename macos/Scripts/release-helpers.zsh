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

# Only the newest release keeps its files. Earlier releases stay on GitHub with their notes,
# but their DMGs and checksums are deleted: Sparkle and the site only ever fetch the newest.
prune_earlier_release_assets() {
    local version="$1" repo="ayhangad/Crenel" tag asset failed=0
    for tag in $(gh release list --repo "${repo}" --limit 100 --json tagName --jq '.[].tagName'); do
        [[ "${tag}" == "v${version}" ]] && continue
        for asset in $(gh release view "${tag}" --repo "${repo}" --json assets --jq '.assets[].name'); do
            gh release delete-asset "${tag}" "${asset}" --repo "${repo}" --yes || failed=1
        done
    done
    return ${failed}
}

# The website (crenel.ayhan.fyi) reads "Latest" from GitHub Releases at build time, so it
# is rebuilt once the release is public. Credentials: CRENEL_DOKPLOY_URL and
# CRENEL_DOKPLOY_API_KEY, or the host.gad.works pair in ~/.config/dokploy/.env.
crenel_website_application_id="GaZUfqz9xrA_0kQ06yb1z"

dokploy_credentials() {
    local url="${CRENEL_DOKPLOY_URL:-}" key="${CRENEL_DOKPLOY_API_KEY:-}" file="${HOME}/.config/dokploy/.env" line candidate=""
    if [[ -z "${url}" || -z "${key}" ]] && [[ -f "${file}" ]]; then
        url="" key=""
        while IFS= read -r line; do
            case "${line}" in
                DOKPLOY_URL=*) candidate="${line#DOKPLOY_URL=}" ;;
                DOKPLOY_API_KEY=*) [[ "${candidate}" == *host.gad.works* ]] && { url="${candidate}"; key="${line#DOKPLOY_API_KEY=}"; } ;;
            esac
        done < "${file}"
    fi
    [[ -n "${url}" && -n "${key}" ]] || return 1
    print -r -- "${url%/}"
    print -r -- "${key}"
}

redeploy_website() {
    local credentials url key
    credentials="$(dokploy_credentials)" || { print -u2 "WARN: no Dokploy credentials; redeploy the website by hand."; return 1; }
    url="${credentials%%$'\n'*}"
    key="${credentials#*$'\n'}"
    curl -sf -X POST "${url}/api/application.redeploy" \
        -H "x-api-key: ${key}" -H 'Content-Type: application/json' \
        -d "{\"applicationId\":\"${crenel_website_application_id}\"}" >/dev/null \
        || { print -u2 "WARN: website redeploy request failed; redeploy it by hand."; return 1; }
}

# Waits (up to ~5 min) until the live home page names this version.
wait_for_website_version() {
    local version="$1" attempt
    for attempt in {1..30}; do
        curl -sf https://crenel.ayhan.fyi/ | grep -q "Crenel ${version} is here" && return 0
        sleep 10
    done
    return 1
}
