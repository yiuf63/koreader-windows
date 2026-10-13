#!/bin/bash
# Find duplicate libraries in a Windows build or package.
#
# Content-based, so it reports one library under two names and does not mistake
# two different libraries that happen to share a prefix. Reports whether each
# duplicate is still referenced, which decides what can be removed.
#
# Part of the win32 duplication work: 15 libraries used to ship twice (137 MB,
# libtesseract alone 107 MB) because `ffi/loadlib.lua` asks for
# `lib<name>-<version>.dll` while a DLL's import table records the producer's own
# spelling -- PE has no soname, so the two have to match on disk.
#
# `check_single_copies.sh` is the CI-facing form of this: it fails when a
# duplicate exists. This one explains the situation, for when it does.
#
# Usage: tools/win32/report_duplicate_libs.sh [koreader-dir]
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KD="${1:-$ROOT/koreader-win32-x86_64-w64-mingw32/koreader}"
LIBS="$KD/libs"

if [ ! -d "$LIBS" ]; then
    echo "error: no libs/ in $KD" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

(
    cd "$LIBS" || exit 1
    for f in *.dll; do
        [ -e "$f" ] || continue
        printf '%s %s\n' "$(md5sum "$f" | cut -d' ' -f1)" "$f"
    done | sort > "$WORK/sums.txt"
)
awk '{ if ($1 == prev) print name "\t" $2; prev = $1; name = $2 }' \
    "$WORK/sums.txt" > "$WORK/dups.txt"

# What every binary in the tree imports, so a duplicate that is still needed can
# be told from one that is merely left over.
while IFS= read -r f; do
    [ -e "$f" ] || continue
    objdump -p "$f" 2>/dev/null | sed -n 's/^\s*DLL Name: //p'
done < <(find -L "$KD" \( -name '*.dll' -o -name '*.exe' \) 2>/dev/null) | sort -u > "$WORK/imports.txt"

printf '%-30s %-30s %-8s %s\n' "name" "duplicate of" "size" "referenced by"
printf '%-30s %-30s %-8s %s\n' "----" "------------" "----" "-------------"

pairs=0
total=0

while IFS=$'\t' read -r a b; do
    [ -n "$a" ] || continue
    pairs=$((pairs + 1))
    size=$(stat -c %s "$LIBS/$a")

    # A duplicate that nothing imports is free to delete; one that something
    # imports needs that dependent relinked first, or it will fail to load.
    who=""
    other=$b
    if grep -qix "$a" "$WORK/imports.txt"; then
        who=$(for f in "$LIBS"/*.dll; do
                  objdump -p "$f" 2>/dev/null | grep -qi "DLL Name: $a" && basename "$f"
              done | tr '\n' ' ')
    fi
    [ -z "$who" ] && who="(nothing imports it)"

    printf '%-30s %-30s %-8s %s\n' "$a" "$other" \
        "$(awk -v s="$size" 'BEGIN{printf "%.1fMB", s/1048576}')" "$who"
    total=$((total + size))
done < "$WORK/dups.txt"

echo ""
if [ "$pairs" -eq 0 ]; then
    echo "  no duplicates: $(ls "$LIBS"/*.dll 2>/dev/null | wc -l) libraries, each distinct"
    exit 0
fi

echo "  duplicate pairs: $pairs"
echo "  wasted in the zip: $((total / 1048576)) MB"
echo ""
echo "  A duplicate nothing imports is left over and can be removed. One that is"
echo "  still imported needs its dependents relinked so their import tables name"
echo "  the canonical file; relinking without that will not fail until load time."
