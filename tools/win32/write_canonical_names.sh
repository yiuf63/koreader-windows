#!/bin/bash
# Write the list of canonical library names for the build.
#
# `libs/` holds each library under two names while the duplication is being
# removed: the canonical `lib<name>-<version>.dll` that `set_libname` declares and
# `ffi/loadlib.lua` asks for, and the producer's own spelling that import tables
# still reference. Operations that rewrite import archives have to act on the
# canonical ones only — processing both means each undoes the other, and the
# result depends on directory order.
#
# The list is derived from the thirdparty CMakeLists files, which is where the
# canonical names are declared, rather than by guessing from the file names: a
# library whose canonical name carries no version (`liblodepng.dll`) is
# indistinguishable from an alias by name alone.
#
# Written beside the build rather than into `libs/`, because `libs/` is what gets
# copied into the release: a list of build metadata there would ship to users, who
# have no use for it.
#
# Usage: tools/win32/write_canonical_names.sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BT="$ROOT/base/thirdparty"
BUILD="$ROOT/base/build/x86_64-w64-mingw32"
OUT="$BUILD/.canonical-names"

mkdir -p "$(dirname "$OUT")"
: > "$OUT"

for f in "$BT"/*/CMakeLists.txt; do
    grep -oE 'append_shared_lib_install_commands\(INSTALL_CMD [^)]*\)' "$f" 2>/dev/null \
    | while IFS= read -r c; do
        args=${c#append_shared_lib_install_commands(INSTALL_CMD }
        args=${args%)}

        # `${LIB_SPEC}` means the name comes from a variable set in the same file.
        case "$args" in
            '${LIB_SPEC}')
                spec=$(grep -ohE 'set\(LIB_SPEC [^)]*\)' "$f" 2>/dev/null | head -1)
                [ -n "$spec" ] || continue
                args=${spec#set(LIB_SPEC }
                args=${args%)}
                ;;
        esac

        name=${args%% *}
        rest=${args#* }
        if [ "$rest" != "$args" ]; then
            ver=${rest#VERSION }
            ver=${ver%% *}
            [ "$ver" != "$rest" ] && printf 'lib%s-%s.dll\n' "$name" "$ver" && continue
        fi
        printf 'lib%s.dll\n' "$name"
    done
done | sort -u > "$OUT"

# A `set_libname(LIB ${LIB_SPEC})` project (mupdf, freetype2) declares its name
# through LIB_SPEC alone, so pick those up too.
for f in "$BT"/*/CMakeLists.txt; do
    grep -q 'set_libname(LIB ${LIB_SPEC})' "$f" 2>/dev/null || continue
    spec=$(grep -ohE 'set\(LIB_SPEC [^)]*\)' "$f" 2>/dev/null | head -1)
    [ -n "$spec" ] || continue
    args=${spec#set(LIB_SPEC }
    args=${args%)}
    name=${args%% *}
    rest=${args#* }
    if [ "$rest" != "$args" ]; then
        ver=${rest#VERSION }
        ver=${ver%% *}
        [ "$ver" != "$rest" ] && printf 'lib%s-%s.dll\n' "$name" "$ver" >> "$OUT" && continue
    fi
    printf 'lib%s.dll\n' "$name" >> "$OUT"
done
sort -u -o "$OUT" "$OUT"

echo "  wrote $(wc -l < "$OUT") canonical names to $OUT"
