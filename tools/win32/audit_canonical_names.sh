#!/bin/bash
# Audit that every import in a build names a canonical library file.
#
# The objective behind the duplication work: each library exists once, under the
# canonical `lib<name>-<version>.dll` that `ffi/loadlib.lua` and `set_libname`
# ask for, and every import table agrees with that name. `check_single_copies.sh`
# asks whether anything is broken; this asks whether the naming is *uniform*,
# which is the property that keeps it from breaking again.
#
# Three legitimate shapes for a name in `libs/`:
#
#   canonical   declared by a thirdparty CMakeLists (`libz-1.dll`), or
#   unversioned declared without a version (`liblodepng.dll`), or
#   external    supplied by the toolchain or the build rather than a project
#               (`lua51.dll`, `libwinpthread-1.dll`), or produced by an
#               `ffi_target` (`libwrap-mupdf.dll`).
#
# An import naming anything else is a library being referenced by a spelling
# this build does not treat as canonical -- which is how the duplication started,
# and what would bring it back.
#
# Usage: tools/win32/audit_canonical_names.sh [koreader-dir]
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KD="${1:-${ROOT}/koreader-win32-x86_64-w64-mingw32/koreader}"
LIBS="${KD}/libs"

if [ ! -d "${LIBS}" ]; then
    echo "error: no libs/ in ${KD}" >&2
    exit 1
fi

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# Canonical names, from the declarations rather than from the file names: a
# library whose canonical name carries no version looks exactly like a leftover
# by name alone.
#
# Regenerated here rather than read from the package. It lives beside the build
# (`base/build/.../.canonical-names`), not in `libs/`, because `libs/` is copied
# into the release and build metadata has no business shipping to users.
sh "${ROOT}/tools/win32/write_canonical_names.sh" >/dev/null 2>&1 || true
if [ -s "${ROOT}/base/build/x86_64-w64-mingw32/.canonical-names" ]; then
    cp "${ROOT}/base/build/x86_64-w64-mingw32/.canonical-names" "${W}/canonical.txt"
else
    # Nothing to compare against: report it rather than silently classifying
    # every name as undeclared.
    echo "warning: no canonical-name list; run write_canonical_names.sh" >&2
    : >"${W}/canonical.txt"
fi

# Everything shipped, and what is imported.
(
    cd "${LIBS}" || exit 1
    for f in *.dll; do [ -e "${f}" ] && printf '%s\n' "${f}"; done
) | sort >"${W}/shipped.txt"

while IFS= read -r f; do
    [ -e "${f}" ] || continue
    objdump -p "${f}" 2>/dev/null | sed -n 's/^\s*DLL Name: //p'
done < <(find -L "${KD}" \( -name '*.dll' -o -name '*.exe' \) 2>/dev/null) | sort -u >"${W}/imported.txt"

# Names imported from *this* tree (a system DLL is not our business).
comm -12 "${W}/imported.txt" "${W}/shipped.txt" >"${W}/imported-here.txt"

sysroot="${SYSTEMROOT:-C:\\Windows}"
sysdir="$(printf '%s' "${sysroot}" | sed 's|\\|/|g; s|^\([A-Za-z]\):|/\L\1|')/System32"

# Names produced by an `ffi_target`: these are built from the koreader
# CMakeLists rather than a thirdparty project, so they appear in neither the
# canonical list nor the toolchain set. Collected from the declaration
# (`ffi_target(<name> ...)` and its OUTPUT) so they are recognised rather than
# reported as unknown every run -- a report that always has entries in it is one
# people stop reading.
grep -ohE '^ffi_target\([a-zA-Z0-9_-]+' "${ROOT}/base/cmake/CMakeLists.txt" 2>/dev/null |
    sed 's/^ffi_target(//' | sort -u >"${W}/ffi-names.txt"

printf '%-34s %-10s %s\n' "shipped library" "class" "canonical?"
printf '%-34s %-10s %s\n' "---------------" "-----" "----------"

unclassified=0
while IFS= read -r name; do
    [ -n "${name}" ] || continue
    if grep -qix "${name}" "${W}/canonical.txt"; then
        cls="canonical"
        verdict="yes"
    else
        # Not declared by a thirdparty project. Either the toolchain, or an
        # `ffi_target` built from the koreader CMakeLists.
        stem=${name#lib}
        stem=${stem%.dll}
        case "${name}" in
            lua51.dll | libwinpthread-1.dll | libgcc_s_seh-1.dll | libstdc++-6.dll)
                cls="toolchain"
                verdict="n/a"
                ;;
            libkoreader-* | libblitbuffer.dll | libwrap-mupdf.dll | libtffi_wrap.dll)
                # `libkoreader-cre` and friends come from `ffi_target` too, and
                # follow the same `lib<name>.dll` shape.
                cls="ffi"
                verdict="n/a"
                ;;
            *)
                if grep -qix "${stem}" "${W}/ffi-names.txt"; then
                    cls="ffi"
                    verdict="n/a"
                else
                    cls="undeclared"
                    verdict="UNKNOWN"
                    unclassified=$((unclassified + 1))
                fi
                ;;
        esac
    fi

    # Is it actually imported by anything?
    if grep -qix "${name}" "${W}/imported-here.txt"; then
        used="imported"
    else
        used="not imported by name"
    fi

    printf '%-34s %-10s %-9s %s\n' "${name}" "${cls}" "${verdict}" "${used}"
done <"${W}/shipped.txt"

echo ""
echo "  shipped:      $(wc -l <"${W}/shipped.txt")"
echo "  declared:     $(wc -l <"${W}/canonical.txt")"
echo "  imported:     $(wc -l <"${W}/imported-here.txt") names from this tree"
echo "  undeclared:   ${unclassified}"

# Every imported name has to exist, or the loader fails at run time.
missing=0
while IFS= read -r dep; do
    [ -n "${dep}" ] || continue
    grep -qix "${dep}" "${W}/shipped.txt" && continue
    [ -f "${sysdir}/${dep}" ] && continue
    printf '  MISSING: %s is imported but not shipped\n' "${dep}"
    missing=$((missing + 1))
done <"${W}/imported.txt"

echo ""
if [ "${missing}" -gt 0 ]; then
    echo "  FAIL: ${missing} import(s) name a file that is not shipped"
    exit 1
fi

if [ "${unclassified}" -gt 0 ]; then
    echo "  NOTE: ${unclassified} shipped name(s) are not declared by any project."
    echo "        Expected for toolchain and ffi_target output; anything else is"
    echo "        a library whose canonical name should be declared so that the"
    echo "        duplication checks know which spelling to keep."
    exit 0
fi

echo "  all imports resolve, and every shipped name is accounted for"
