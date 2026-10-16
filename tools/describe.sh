#!/usr/bin/env bash

set -eo pipefail

if [[ -n "${CLIFORCE_COLOR}" ]] || [[ -t 2 ]]; then
    declare -r ANSI_MAGENTA=$'\033[35;1m'
    declare -r ANSI_RESET=$'\033[0m'
else
    declare -r ANSI_MAGENTA=''
    declare -r ANSI_RESET=''
fi

export TZ=UTC

release_date="$(git show -s --format=format:"%cd" --date=short HEAD)"

if out="$(git describe --match='v[0-9]*' HEAD 2>&1)"; then
    version="${out}"
    # The tag, for `git log`'s date. Not `${version%%-*}`: that takes the text up
    # to the *first* hyphen, which is only the whole tag when the tag has none.
    # `v2026.10-win32.5` became `v2026.10` that way, and `git log -1 v2026.10`
    # then failed with "ambiguous argument" -- no such revision, and the build
    # stopped at "failed to determine version".
    #
    # `git describe` appends `-<commits>-g<sha>` only when HEAD is ahead of the
    # tag, so strip that suffix when it is there and otherwise the tag is the
    # whole string.
    case "${version}" in
        *-[0-9]*-g[0-9a-f]*) epoch_rev="${version%-*-g*}" ;;
        *) epoch_rev="${version}" ;;
    esac
else
    # No tag, shallow clone?
    printf '%s\n' "${ANSI_MAGENTA}WARNING: cannot describe current git revision:${ANSI_RESET} ${out}" 1>&2
    version="v0000.00-0-g$(git rev-parse --short=10 @)"
    epoch_rev='@'
fi
# Only append date if we're not on a whole version, like v2018.11.
case "${version}" in *-*) version="${version}_${release_date}" ;; esac

release_epoch="$(git log -1 --format='%cs' "${epoch_rev}")"

printf '%s\n' "${version}" "${release_date}" "${release_epoch}"
