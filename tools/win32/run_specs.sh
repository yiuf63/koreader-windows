#!/bin/bash
# Run KOReader's frontend spec suite against the Windows build.
#
# Why this exists instead of `./kodev test front`:
#
#   * The normal harness drives `busted`, which comes from luarocks and is only
#     built for the emulator target — there is no busted for win32.
#   * It runs the specs under `luajit`, but this build's `luajit.exe` exports
#     none of the POSIX shims `koreader.exe` provides (see base/win32_posix.c),
#     so the frontend cannot even load there.
#   * A few specs hard-crash the process (they drive the real document and
#     framebuffer stack). Running one spec per process means a crash costs only
#     that spec, and the rest of the suite still reports.
#
# `spec_runner.lua` supplies the slice of busted's API the specs use; it is
# installed as a user patch, because that is the only way to execute Lua inside
# a running koreader.
#
# Usage: tools/win32/run_specs.sh [koreader-dir]

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KD="${1:-$ROOT/koreader-win32-x86_64-w64-mingw32/koreader}"
TMP="${TEMP:-/tmp}"
DETAIL="$TMP/kospecs_detail"
OUT="$TMP/kospecs_all.txt"

# Keep the run self-contained. `KO_HOME` sets the data directory outright (it
# takes priority over APPDATA in datastorage.lua) and the patch directory lives
# inside it, so nothing here touches a real profile.
SCRATCH="${TMPDIR:-/tmp}/ko-specs"
export KO_HOME
KO_HOME="$(cygpath -w "$SCRATCH/home" 2>/dev/null || echo "$SCRATCH/home")"
SCRATCH_U="${SCRATCH}/home"
PATCHDIR="$SCRATCH_U/patches"

if [ ! -x "$KD/koreader.exe" ]; then
    echo "error: no koreader.exe in $KD" >&2
    echo "       build it first: make TARGET=win32 update-zip" >&2
    exit 1
fi

# Several specs open example documents through `spec/front/unit/data`, which the
# emulator harness links from `test/`; there is no such step for this target.
if [ ! -d "$ROOT/spec/front/unit/data" ]; then
    mkdir -p "$ROOT/spec/front/unit"
    ln -sfn ../../../test "$ROOT/spec/front/unit/data" 2>/dev/null \
        || cp -r "$ROOT/test" "$ROOT/spec/front/unit/data"
fi

rm -rf "$SCRATCH_U" "$DETAIL"
mkdir -p "$DETAIL" "$PATCHDIR"
cp -f "$ROOT/tools/win32/spec_runner.lua" "$PATCHDIR/2-spec-runner.lua"

: > "$OUT"
specs=$(ls "$ROOT"/spec/unit/*_spec.lua | xargs -n1 basename | sort)

pass_total=0
fail_total=0
crash_list=""

for s in $specs; do
    rm -f "$TMP/kotest_one.txt"
    printf '%s' "$s" > "$TMP/kospec_name.txt"

    ( cd "$KD" && ./koreader.exe >/dev/null 2>&1 ) &
    pid=$!
    # Bounded wait: some specs sit on timers, and a hung one should not stall
    # the whole run.
    for _ in $(seq 1 60); do
        kill -0 $pid 2>/dev/null || break
        sleep 0.5
    done
    if kill -0 $pid 2>/dev/null; then
        kill $pid 2>/dev/null; wait $pid 2>/dev/null
        echo "TIMEOUT  $s" >> "$OUT"; crash_list="$crash_list $s"; continue
    fi
    wait $pid 2>/dev/null

    if [ -f "$TMP/kotest_one.txt" ] && grep -q '^DONE' "$TMP/kotest_one.txt"; then
        cp "$TMP/kotest_one.txt" "$DETAIL/$s.txt"
        p=$(sed -n 's/^passed: //p' "$TMP/kotest_one.txt")
        f=$(sed -n 's/^failed: //p' "$TMP/kotest_one.txt")
        pass_total=$((pass_total + ${p:-0}))
        fail_total=$((fail_total + ${f:-0}))
        echo "ok       $s  passed=${p:-0} failed=${f:-0}" >> "$OUT"
    else
        cp "$TMP/kotest_one.txt" "$DETAIL/$s.txt" 2>/dev/null || true
        echo "CRASH    $s" >> "$OUT"
        crash_list="$crash_list $s"
    fi
done

{
    echo ""
    echo "==================== summary ===================="
    echo "spec files : $(echo "$specs" | wc -l)"
    echo "assertions : passed=$pass_total failed=$fail_total"
    echo "crashed    : $(echo "$crash_list" | tr ' ' '\n' | grep -c .)"
    for c in $crash_list; do echo "   - $c"; done
    echo ""
    echo "per-spec detail: $DETAIL"
} >> "$OUT"

cat "$OUT"

# Exit status.
#
# Not "all specs pass": many need the emulator harness (screen geometry, the
# framebuffer) or parts of luassert this runner does not implement, so a
# zero-failure run is not the bar here. What must not happen is the suite
# collapsing — a build that cannot even load the frontend, or a change that
# breaks whole groups of specs.
#
#   MIN_PASS  floor on passing assertions (262 at the time of writing)
#   MAX_CRASH specs that crash or hang the process (0 at the time of writing)
MIN_PASS="${MIN_PASS:-250}"
MAX_CRASH="${MAX_CRASH:-5}"

crashes=$(echo "$crash_list" | tr ' ' '\n' | grep -c .)

if [ "$pass_total" -lt "$MIN_PASS" ]; then
    echo "" >&2
    echo "FAILED: only $pass_total assertions passed (expected at least $MIN_PASS)" >&2
    exit 1
fi

if [ "$crashes" -gt "$MAX_CRASH" ]; then
    echo "" >&2
    echo "FAILED: $crashes spec(s) crashed or timed out (allowed: $MAX_CRASH)" >&2
    exit 1
fi

exit 0
