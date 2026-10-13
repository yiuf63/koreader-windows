#!/bin/bash
# Verify that no library is shipped twice and no import uses a stale name.
#
# Why this exists as a check rather than a note
# --------------------------------------------
# The Windows package used to carry 15 libraries twice -- 137 MB, libtesseract
# alone 107 MB -- because two naming conventions had to be satisfied at once.
# `ffi/loadlib.lua` asks for `lib<name>-<version>.dll`, while a DLL's own import
# table records its dependencies as literal file names, fixed at link time from
# the import archive it was linked against. PE has no soname, so those names have
# to match what is on disk exactly.
#
# The fix makes both sides agree on the canonical name, so one file per library
# suffices. It is easy to undo by accident, though, and the failure is quiet:
#
#   * adding a library that links a producer's own spelling brings the second
#     copy back, costing tens of megabytes with nothing to show for it;
#   * relinking without the import archive being rewritten points an import at a
#     name that is no longer shipped -- which does not fail here, but at load
#     time on a user's machine, with error 126 or 127 naming neither the module
#     nor the symbol.
#
# Both are cheap to detect by looking at the artifact, so they are checked here.
#
# Usage: tools/win32/check_single_copies.sh <koreader-dir>
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KD="${1:-$ROOT/koreader-win32-x86_64-w64-mingw32/koreader}"

if [ ! -d "$KD/libs" ]; then
    echo "error: no libs/ in $KD" >&2
    exit 1
fi

LIBS="$KD/libs"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0

# --- 1. identical content under two names -----------------------------------
#
# Compared by content, not by name: a library whose canonical name carries no
# version (`liblodepng.dll`) is indistinguishable from an alias by name alone,
# and `lua51.dll` and `libwinpthread-1.dll` come from the toolchain rather than
# from a thirdparty project. An alias is a file that duplicates another file.
# Compare by content, in the directory itself so the reported names are just the
# file names. `md5sum` prints the path it was given, and a glob hands it the full
# one; running from $LIBS keeps the output readable.
(
    cd "$LIBS" || exit 1
    for f in *.dll; do
        [ -e "$f" ] || continue
        # `cut` drops md5sum's mode marker (`*` for binary), which would
        # otherwise end up in the printed file name.
        printf '%s %s\n' "$(md5sum "$f" | cut -d' ' -f1)" "$f"
    done | sort > "$WORK/sums.txt"
)
awk '{ if ($1 == prev) print name "\t" $2; prev = $1; name = $2 }' \
    "$WORK/sums.txt" > "$WORK/dups.txt"

if [ -s "$WORK/dups.txt" ]; then
    echo "FAIL: libraries shipped twice"
    while IFS=$'\t' read -r a b; do
        size=$(stat -c %s "$LIBS/$b" 2>/dev/null || echo 0)
        printf '  %-28s == %-28s (%s MB)\n' "$a" "$b" \
            "$(awk -v s="$size" 'BEGIN{printf "%.1f", s/1048576}')"
    done < "$WORK/dups.txt"
    echo ""
    echo "  Each of these is one library under two names. The canonical name is"
    echo "  the one to keep; the other is whatever its producer emitted, which"
    echo "  should have been rewritten out of the import archives."
    fail=1
else
    echo "ok: no library is shipped twice ($(ls "$LIBS"/*.dll 2>/dev/null | wc -l) libraries)"
fi

# --- 2. imports that name a file which is not shipped -----------------------
#
# This is the load-time failure described above, caught at package time.
shipped=$(mktemp)
find -L "$KD" -name '*.dll' 2>/dev/null | while IFS= read -r f; do basename "$f"; done \
    | sort -u > "$shipped"

# The system directory, so a genuine Windows DLL is not reported as missing.
sysroot="${SYSTEMROOT:-C:\\Windows}"
sysdir="$(printf '%s' "$sysroot" | sed 's|\\|/|g; s|^\([A-Za-z]\):|/\L\1|')/System32"

bad=$(mktemp)
n=0
while IFS= read -r f; do
    [ -e "$f" ] || continue
    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        grep -qix "$dep" "$shipped" && continue
        [ -f "$sysdir/$dep" ] && continue
        printf '  %s needs %s\n' "$(basename "$f")" "$dep" >> "$bad"
        n=$((n + 1))
    done < <(objdump -p "$f" 2>/dev/null | sed -n 's/^\s*DLL Name: //p')
done < <(find -L "$KD" \( -name '*.dll' -o -name '*.exe' \) 2>/dev/null)

if [ "$n" -gt 0 ]; then
    echo "FAIL: $n import(s) name a file that is not shipped"
    echo ""
    cat "$bad"
    echo ""
    echo "  A dependent that records a name this build no longer ships was"
    echo "  linked before its import archive was rewritten. It fails at load"
    echo "  time, not here, so it is worth relinking rather than shipping."
    fail=1
else
    echo "ok: every import resolves to a shipped file or a system DLL"
fi

echo ""
if [ "$fail" -eq 0 ]; then
    echo "SINGLE COPIES OK"
    exit 0
fi
echo "SINGLE COPIES FAILED"
exit 1
