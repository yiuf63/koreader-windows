#!/bin/bash
# Dump the state of every process that belongs to the build.
#
# The point is a hang: `ninja` buffers a command's output until that command
# exits, so a step that never returns writes nothing, and the build log stops at
# whatever finished last. This samples the process table instead, which does not
# depend on any output being produced.
#
# What it records per process, and why each field matters:
#
#   State:  S (sleeping), R (running), D (uninterruptible), Z (zombie), T (stopped)
#           A `cmake` that is `S` is waiting on something -- its fd list says on
#           what. A `cmake` that is `R` for minutes is spinning, which is a
#           different bug. A `Z` means the parent is not reaping, which is a third.
#   fd:     open descriptors, with the real path each points at. Two `cmake`
#           processes contend for the same file if both hold it, and a `cmake`
#           holding a pipe nobody drains never finishes.
#   cwd:    which thirdparty project it is working on.
#
# Usage: tools/win32/dump-process-state.sh [outfile]
#
# Appends, so it can run as a 30-second heartbeat and keep a history.

set -u

OUT="${1:-${RUNNER_TEMP:-/tmp}/build-process-state.log}"

sample() {
    printf '=== %s ===\n' "$(date -u +%H:%M:%SZ)"

    # `ps` without `-W` lists only the MSYS processes, which is what the build
    # runs as. Its first column is the PID that `/proc` is keyed on; the Windows
    # PID further along is not.
    ps 2>/dev/null | tail -n +2 | while read -r pid _; do
        [ -n "${pid}" ] || continue

        cmd=$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null | cut -c1-140)
        [ -n "${cmd}" ] || continue

        state=$(sed -n 's/^State:\s*//p' "/proc/${pid}/status" 2>/dev/null)
        cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null | sed 's|.*/build/thirdparty/|tp/|')

        printf '  [%s] state=%s cwd=%s\n' "${cmd}" "${state:-?}" "${cwd}"
        printf '       cmd=%s\n' "${cmd}"

        # Descriptors, with targets. The build's own files are what matter; the
        # noise (`/dev/null`, the console, the MSYS pipe pair every process has)
        # is dropped so the interesting ones stand out.
        for fd in /proc/"${pid}"/fd/*; do
            [ -e "${fd}" ] || continue
            tgt=$(readlink "${fd}" 2>/dev/null)
            [ -n "${tgt}" ] || continue
            printf '%s\n' "${tgt}" | grep -qE '^(/dev/(null|console|tty)|.*/msys-)' && continue
            printf '       fd %s -> %s\n' "$(basename "${fd}")" "${tgt}"
        done
    done
}

if [ "${1:-}" = "--once" ]; then
    sample
else
    while :; do
        sample >>"${OUT}" 2>&1
        sleep 30
    done
fi
