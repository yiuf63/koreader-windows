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
PATCHDIR="${APPDATA:-$HOME/AppData/Roaming}/koreader/patches"
TMP="${TEMP:-/tmp}"
DETAIL="$TMP/kospecs_detail"
OUT="$TMP/kospecs_all.txt"

if [ ! -x "$KD/koreader.exe" ]; then
    echo "error: no koreader.exe in $KD" >&2
    echo "       build it first: make TARGET=win32 update-zip" >&2
    exit 1
fi

rm -rf "$DETAIL"; mkdir -p "$DETAIL"
mkdir -p "$PATCHDIR"
rm -f "$PATCHDIR"/*.lua
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
