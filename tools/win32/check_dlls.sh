#!/bin/bash
# Check that every DLL in the Windows build can resolve its imports.
#
# The build's `bincheck` target is not usable here: it looks for `libc.so.6` and
# reasons about ELF sonames. PE has no soname — a DLL records its dependencies
# by literal file name, resolved from the executable's directory and the DLL
# search path — so the check is simply "is there a file with that name in
# `libs/`, `common/`, next to the exe, or in the system directory".
#
# This catches the failure mode that otherwise only appears at runtime, and only
# when the affected code path is exercised:
#
#     cannot load module 'libs/libkoreader-monolibtic.dll'
#
# Usage: tools/win32/check_dlls.sh [koreader-dir]

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KD="${1:-${ROOT}/koreader-win32-x86_64-w64-mingw32/koreader}"

# `libs/` is a *symlink* into the build tree, and creating one on Windows needs
# SeCreateSymbolicLinkPrivilege. GitHub's runners do not grant it, so `ln -s`
# silently produces nothing there and the install tree comes out without `libs`
# (or `common`). Rather than fail the check on that -- the DLLs exist, they are
# just one directory over -- resolve the build tree directly.
#
# `-e` rather than `-d`: a symlink whose target is missing is not a directory,
# and that is exactly the broken case to fall through.
if [ ! -d "${KD}/libs" ]; then
    build_libs="${ROOT}/base/build/x86_64-w64-mingw32/libs"
    if [ -d "${build_libs}" ]; then
        echo "note: ${KD}/libs is absent (symlink not created); using ${build_libs}" >&2
        LIBS_DIR="${build_libs}"
        COMMON_DIR="${ROOT}/base/build/x86_64-w64-mingw32/common"
    else
        echo "error: no libs/ in ${KD}, and no ${build_libs} — build first" >&2
        exit 1
    fi
else
    LIBS_DIR="${KD}/libs"
    COMMON_DIR="${KD}/common"
fi

command -v objdump >/dev/null 2>&1 || {
    echo "error: objdump not found (install binutils)" >&2
    exit 1
}

# Windows ships these; they are not part of the build.
system_dlls="
advapi32.dll bcrypt.dll cfgmgr32.dll comctl32.dll comdlg32.dll comsuppw.dll
crypt32.dll d2d1.dll d3d11.dll d3d9.dll dwmapi.dll dwrite.dll dxgi.dll
gdi32.dll gdi32full.dll hid.dll imm32.dll iphlpapi.dll kernel32.dll
mf.dll mfplat.dll mfreadwrite.dll mfuuid.dll msimg32.dll msvcp_win.dll
msvcrt.dll ncrypt.dll netapi32.dll ntdll.dll ole32.dll oleaut32.dll
opengl32.dll powrprof.dll propsys.dll psapi.dll rpcrt4.dll sechost.dll
secur32.dll setupapi.dll shcore.dll shell32.dll shlwapi.dll
sspicli.dll user32.dll userenv.dll uxtheme.dll version.dll winhttp.dll
wininet.dll winmm.dll winspool.drv winstrm.dll ws2_32.dll wspiapi.h
wsock32.dll wtsapi32.dll xmllite.dll dbghelp.dll api-ms-win-*.dll
ext-ms-*.dll ucrtbase.dll vcruntime*.dll msvcp*.dll
"

is_system() {
    local want="${1,,}"
    for s in ${system_dlls}; do
        # shellcheck disable=SC2053
        [[ "${want}" == ${s} ]] && return 0
    done
    return 1
}

# Everywhere the loader will look, in the order PE uses.
search_dirs="${KD} ${LIBS_DIR} ${COMMON_DIR} /c/Windows/System32"

resolve() {
    local want="$1"
    for d in ${search_dirs}; do
        [ -f "${d}/${want}" ] && return 0
    done
    return 1
}

missing_total=0
checked=0

for dll in "${KD}"/*.dll "${LIBS_DIR}"/*.dll "${COMMON_DIR}"/*.dll; do
    [ -f "${dll}" ] || continue
    checked=$((checked + 1))
    name="$(basename "${dll}")"

    while read -r dep; do
        [ -n "${dep}" ] || continue
        is_system "${dep}" && continue
        resolve "${dep}" && continue
        echo "MISSING  ${name} -> ${dep}"
        missing_total=$((missing_total + 1))
    done < <(objdump -p "${dll}" 2>/dev/null |
        sed -n 's/^\s*DLL Name: //p' |
        sed 's/[[:space:]]*$//')
done

if [ "${missing_total}" -eq 0 ]; then
    echo "ok: ${checked} DLLs, all imports resolvable"
    exit 0
fi

echo ""
echo "${missing_total} unresolved import(s) across ${checked} DLLs" >&2
exit 1
