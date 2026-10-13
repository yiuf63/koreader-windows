#!/bin/bash
# Report whether a Windows package contains the fixes it should.
#
# Used to check a CI-built artifact, which is a *different* build from a local
# one: the runner checks out with autocrlf, builds with a release configuration
# (stripped binaries), and repacks. So "CI is green" does not by itself say the
# artifact behaves like the locally built one.
set -u

KD="${1:?usage: check_package.sh <koreader-dir>}"

if [ ! -d "$KD" ]; then
    echo "error: no such directory: $KD" >&2
    exit 1
fi

pass=0
fail=0
check() {
    local name="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        printf '  ok    %-46s %s\n' "$name" "$got"
        pass=$((pass + 1))
    else
        printf '  FAIL  %-46s got=%s want=%s\n' "$name" "$got" "$want"
        fail=$((fail + 1))
    fi
}

echo "package: $KD"
echo ""

# The startup abort fixed in win32.3: the SDL device needs a home directory on
# Windows, and font_settings must tolerate not having one.
check "device.lua falls back to USERPROFILE" \
    "$(grep -c USERPROFILE "$KD/frontend/device/sdl/device.lua" 2>/dev/null || echo 0)" 2
check "font_settings.lua guards a nil home" \
    "$(grep -c 'home and home' "$KD/frontend/ui/elements/font_settings.lua" 2>/dev/null || echo 0)" 1

# Console handling: QuickEdit must be disabled, and the window hidden on a
# double-click (which needs GetConsoleProcessList to tell the cases apart).
imports=$(objdump -p "$KD/koreader.exe" 2>/dev/null)
for sym in ShowWindow GetConsoleProcessList SetConsoleOutputCP; do
    n=$(printf '%s\n' "$imports" | grep -c "$sym" || true)
    check "koreader.exe imports $sym" "$n" 1
done

# Delivery checks.
check "architecture is x86-64" \
    "$(file -Lb "$KD/koreader.exe" | grep -oE 'x86-64|i386' | head -1)" "x86-64"
check "no stray test.db" \
    "$(find "$KD" -maxdepth 1 -name 'test.db' | wc -l)" 0
check "reader.lua present" \
    "$([ -f "$KD/reader.lua" ] && echo yes || echo no)" yes

echo ""
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
