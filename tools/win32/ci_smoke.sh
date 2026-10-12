#!/bin/bash
# Run the Windows build's runtime smoke test (tools/win32/ci_smoke.lua).
#
# The test has to run inside a real koreader process, and the only way to get
# Lua executed there is to install it as a user patch. KOROOT/APPDATA are
# pointed at a scratch directory so this never touches a real profile.
#
# Usage: tools/win32/ci_smoke.sh [koreader-dir]
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KD="${1:-$ROOT/koreader-win32-x86_64-w64-mingw32/koreader}"

if [ ! -x "$KD/koreader.exe" ]; then
    echo "error: no koreader.exe in $KD" >&2
    exit 1
fi

# Keep the run self-contained: its own data dir, its own patch directory.
# `KO_HOME` sets the data directory outright (it takes priority over APPDATA in
# datastorage.lua), and the patch directory lives inside it.
SCRATCH="${TMPDIR:-/tmp}/ko-ci-smoke"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/home/patches"
cp "$ROOT/tools/win32/ci_smoke.lua" "$SCRATCH/home/patches/2-ci-smoke.lua"

# Resolve where the test writes its result, the same way it does: a Windows
# process sees the Win32 spelling of TEMP, not the MSYS one.
RESULT="$(cygpath -u "${TEMP:-${TMP:-/tmp}}")/ci_smoke.txt"
rm -f "$RESULT"

(
    cd "$KD"
    # The launcher is a GUI binary: it returns immediately, so wait for the
    # patch to finish rather than for the process to exit.
    KO_HOME="$(cygpath -w "$SCRATCH/home")" \
        ./koreader.exe >"$SCRATCH/out.txt" 2>&1 &
    pid=$!

    for _ in $(seq 1 120); do
        [ -f "$RESULT" ] && grep -q '^SMOKE ' "$RESULT" && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.5
    done
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
)

if [ ! -f "$RESULT" ]; then
    echo "error: the smoke test produced no result file at $RESULT" >&2
    echo "--- process output ---" >&2
    cat "$SCRATCH/out.txt" >&2 || true
    exit 1
fi

cat "$RESULT"

if grep -q '^SMOKE OK' "$RESULT"; then
    exit 0
fi

echo "--- process output ---" >&2
cat "$SCRATCH/out.txt" >&2 || true
exit 1
