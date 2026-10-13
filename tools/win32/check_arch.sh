#!/bin/bash
# Report the architecture of every PE file in a KOReader Windows build.
#
# The build target is called `win32`, which is a platform name and says nothing
# about the word size, so this checks the binaries themselves.
set -u

KD="${1:-/d/Code/koreader/koreader-win32-x86_64-w64-mingw32/koreader}"

if [ ! -d "$KD" ]; then
    echo "error: no such directory: $KD" >&2
    exit 1
fi

n64=0
n32=0
other=0
other_list=""

for f in "$KD"/koreader.exe "$KD"/*.dll "$KD"/libs/*.dll "$KD"/common/*.dll; do
    [ -f "$f" ] || continue
    # Follow symlinks: in the build tree these point at the real artefacts.
    t=$(file -Lb "$f" 2>/dev/null)
    case "$t" in
        *"PE32+ "*) n64=$((n64 + 1)) ;;
        *"PE32 "*)  n32=$((n32 + 1)) ;;
        *)          other=$((other + 1)); other_list="$other_list $(basename "$f")" ;;
    esac
done

echo "directory: $KD"
echo ""
echo "  64-bit (PE32+) : $n64"
echo "  32-bit (PE32)  : $n32"
if [ "$other" -ne 0 ]; then
    echo "  unrecognised   : $other ->$other_list"
fi
echo ""
echo "main executable:"
file -Lb "$KD/koreader.exe"
echo ""
echo "PE machine field:"
objdump -f "$KD/koreader.exe" 2>/dev/null | grep -E "file format|architecture" | sed 's/^/  /'
