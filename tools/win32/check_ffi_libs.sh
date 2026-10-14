#!/bin/bash
# Load every FFI library and call into it, to prove the imports resolve.
#
# The duplication work rewrote import archives so that each library is shipped
# once, under the canonical name. That change is invisible to the spec suite: it
# alters which file a DLL loads, not what the Lua code does. So a spec run passes
# whether the libraries resolve or not.
#
# What it *does* affect is whether a library loads at all, and whether the
# symbols the frontend calls are still reachable. A wrong export list produces a
# library that loads and is missing symbols, which surfaces as a nil call far
# from the cause -- exactly the failure mode that made the first attempt at this
# rewrite dangerous (`dlltool --export-all-symbols` read the COFF symbol table,
# so dependents imported `DllMain` and `_chkstk_ms` and failed at load with error
# 127).
#
# `check_ffi_libs.lua` is installed as a user patch, which is the only way to run
# Lua inside a running koreader, and writes its results to the data directory.
#
# Usage: tools/win32/check_ffi_libs.sh [koreader-dir]
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KD="${1:-${ROOT}/koreader-win32-x86_64-w64-mingw32/koreader}"

if [ ! -x "${KD}/koreader.exe" ]; then
    echo "error: no koreader.exe in ${KD}" >&2
    exit 1
fi

SCRATCH="${TMPDIR:-/tmp}/ko-ffi"
export KO_HOME
KO_HOME="$(cygpath -w "${SCRATCH}/home" 2>/dev/null || echo "${SCRATCH}/home")"
SCRATCH_U="${SCRATCH}/home"
PATCHDIR="${SCRATCH_U}/patches"
RESULT="${SCRATCH_U}/ffi-check.txt"

rm -rf "${SCRATCH_U}"
mkdir -p "${PATCHDIR}"
cp -f "${ROOT}/tools/win32/check_ffi_libs.lua" "${PATCHDIR}/2-ffi-check.lua"

# The archive test needs a real document. koreader runs from the package
# directory, where `test/` does not exist, so the path is passed in rather than
# assumed -- a relative path would work only when launched from the checkout.
export KO_TESTDATA
KO_TESTDATA="$(cygpath -w "${ROOT}/test" 2>/dev/null || echo "${ROOT}/test")"

# Run it and wait. The patch writes its file and the process is killed after, so
# there is no need for the reader to exit on its own -- it shows a window and
# waits for input.
(cd "${KD}" && ./koreader.exe >/dev/null 2>&1) &
pid=$!
for _ in $(seq 1 80); do
    [ -f "${RESULT}" ] && break
    kill -0 ${pid} 2>/dev/null || break
    sleep 0.5
done
kill ${pid} 2>/dev/null
wait ${pid} 2>/dev/null

if [ ! -f "${RESULT}" ]; then
    echo "FAIL: the check did not run (no ${RESULT})" >&2
    echo "      the frontend may not have started; run ci_smoke.sh" >&2
    exit 1
fi

cat "${RESULT}"

# The summary line reads `checked=N failed=M`, so the pattern matches the second
# field rather than anchoring at the start of the line -- an anchored `^failed=`
# never matched, and the script reported "did not complete" for a run that had in
# fact passed.
#
# `tr -d '\r'` first: Lua writes the file in text mode, which on Windows turns
# every newline into CRLF, and `$` would then fail against the trailing carriage
# return.
failed=$(tr -d '\r' <"${RESULT}" | sed -n 's/^checked=[0-9]* failed=\([0-9]*\)$/\1/p')
# `${failed:-1}` would replace a legitimate 0, since `:-` treats the empty string
# alike -- but 0 is the answer that means success. The check below distinguishes
# "not found" from "zero".
if [ -z "${failed}" ]; then
    echo "FAIL: no result line in ${RESULT}; the check did not complete" >&2
    exit 1
fi

echo ""
if [ "${failed}" -eq 0 ]; then
    echo "FFI LIBS OK"
    exit 0
fi

echo "FFI LIBS FAILED: ${failed} library/libraries unusable"
exit 1
