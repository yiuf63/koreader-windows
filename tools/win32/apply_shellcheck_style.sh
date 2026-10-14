#!/bin/bash
# Apply shellcheck's SC2250 fixes to the win32 helper scripts.
#
# The repository's `.shellcheckrc` turns on `require-variable-braces`
# (upstream 668eee97f, "[CI] Add curly braces check"), which shellcheck reports
# as SC2250. The lint job runs `.ci/check.sh`, and `.ci/helper_shellchecks.sh`
# collects every tracked shell script with `git grep`, so `tools/win32/*.sh` is
# in scope: a script that ignores the rule fails CI.
#
# Doing this by hand across a dozen files invites exactly the mistakes the rule
# is meant to prevent, so shellcheck makes the edits -- `--format=diff` prints a
# unified diff with only that check enabled.
#
# Two details make its output unusable as-is on Windows:
#
#   * separator: the `---`/`+++` lines are separated by a literal backslash-t
#     (two characters, not a tab), where `git apply` expects a slash;
#   * line endings: the tool emits CRLF here, and `git apply` rejects the patch.
#
# Both are normalised before applying.
#
# Usage: tools/win32/apply_shellcheck_style.sh <shellcheck> <file>...
set -eu

SC="$1"
shift 1

if [ ! -x "${SC}" ]; then
    echo "not executable: ${SC}" >&2
    exit 1
fi

total=0
for f in "$@"; do
    [ -f "${f}" ] || continue

    "${SC}" --shell=bash --enable=require-variable-braces --format=diff "${f}" 2>/dev/null |
        tr -d '\r' |
        sed 's|^--- a\\| --- a/|; s|^+++ b\\|+++ b/|' |
        sed 's|^--- a/|--- a/|; s|^+++ b/|+++ b/|' \
            >/tmp/sc-style.diff || true

    [ -s /tmp/sc-style.diff ] || continue

    if git apply --whitespace=nowarn /tmp/sc-style.diff 2>/dev/null; then
        n=$(grep -c '^+' /tmp/sc-style.diff || true)
        printf '  %-38s %s line(s)\n' "$(basename "${f}")" "$((n - 1))"
        total=$((total + 1))
    else
        printf '  FAILED %s (patch kept at /tmp/sc-style.diff)\n' "${f}" >&2
    fi
done

echo "  ${total} file(s) changed"
