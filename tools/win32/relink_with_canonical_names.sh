#!/bin/bash
# Relink a library and its dependents after its import archive was rewritten.
#
# The ordering here is the whole point, and it is easy to get wrong:
#
#   1. a project's link step *regenerates* its import archive, so any rewrite
#      done before a relink is thrown away;
#   2. a dependent reads the archive at link time, so a rewrite done after it was
#      linked has no effect on that dependent.
#
# So the rewrite has to land between the two: after the library itself is built,
# and before its dependents are linked. `record_canonical_implib.sh` runs at the
# end of each project's install step, which is exactly that moment in a normal
# build from scratch — but a rebuild of an individual target can land on the
# wrong side of it, which is what this repairs.
#
# Usage: tools/win32/relink_with_canonical_names.sh <target>...
#
#   <target>...  ninja targets to relink after rewriting the archives
#
# Rewriting is done for every library installed under libs/, so the archives are
# consistent before any relinking happens.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/base/build/x86_64-w64-mingw32"
MODULES="$ROOT/base/thirdparty/cmake_modules"

if [ ! -d "$BUILD" ]; then
    echo "error: no build directory at $BUILD" >&2
    exit 1
fi

echo "== rewriting import archives for every installed library =="
# Only the canonical `lib<name>-<version>.dll` files are considered, and that is
# not a detail: the alias copies (`libz.dll` beside `libz-1.dll`) would otherwise
# be processed too, and each would rewrite the shared archive back to its own
# spelling. Whichever ran last would win, so the result depended on directory
# order. Comparing against the canonical name each library declares keeps this to
# one rewrite per archive.
CANONICAL="$BUILD/.canonical-names"
if [ ! -s "$CANONICAL" ]; then
    echo "error: $CANONICAL missing; it lists which names are canonical" >&2
    exit 1
fi

count=0
while IFS= read -r base; do
    [ -n "$base" ] || continue
    dll="$BUILD/libs/$base"
    [ -f "$dll" ] || continue
    out=$(sh "$MODULES/record_canonical_implib.sh" "$dll" \
            "$BUILD/staging/lib" \
            "$BUILD"/thirdparty/*/build \
            "$BUILD"/thirdparty/*/build/lib 2>&1) || {
        echo "$out" >&2
        exit 1
    }
    if [ -n "$out" ]; then
        printf '%s\n' "$out" | sed 's/^/  /'
        count=$((count + 1))
    fi
done < "$CANONICAL"
echo "  ($count libraries had an archive rewritten)"
echo ""

if [ "$#" -eq 0 ]; then
    echo "== no targets given; nothing to relink =="
    exit 0
fi

echo "== relinking: $* =="
# `NINJAFLAGS=-j1` bounds the *inner* ninja each project runs: crengine and
# tesseract have translation units that peak near 1 GB, and letting the inner
# build use every core exhausts the machine (`cc1plus.exe: out of memory`).
cd "$BUILD/cmake"
NINJAFLAGS="-j1" ninja -j1 "$@" 2>&1 | tail -20
