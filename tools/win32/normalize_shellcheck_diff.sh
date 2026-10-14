#!/bin/bash
# Turn shellcheck's `--format=diff` output into something `git apply` accepts.
#
# Two things about the raw output make it unusable here, both Windows artifacts:
#
#   * the `---`/`+++` header lines use a literal backslash-t as the separator
#     between the `a`/`b` prefix and the path -- two characters, not a tab --
#     where `git apply` requires a slash;
#   * the tool writes CRLF, and `git apply` rejects a patch whose context lines
#     do not match the file byte for byte.
#
# The separator is found by locating the `a\` / `b\` prefix rather than by a
# fixed column, because the field is not at the same offset on both lines.
#
# Usage: tools/win32/normalize_shellcheck_diff.sh < raw.diff > fixed.diff
set -eu

tr -d '\r' | awk '
    # `--- a\tools/...` -> `--- a/tools/...`
    /^--- a\\/ { print "--- a/" substr($0, 7); next }
    # `+++ b\tools/...` -> `+++ b/tools/...`
    /^\+\+\+ b\\/ { print "+++ b/" substr($0, 7); next }
    { print }
'
