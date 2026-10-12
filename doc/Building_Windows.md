# Building KOReader for Windows

KOReader builds natively for Windows with the MinGW-w64 toolchain from MSYS2:
the result is a normal `koreader.exe` that links against the DLLs in `libs/`,
with no POSIX emulation layer (no Cygwin) involved.

This is a plain `TARGET=win32` build. It is not a separate fork: the changes
live in the regular build system and the frontend, and are meant to follow
upstream.

## Prerequisites

Install [MSYS2](https://www.msys2.org/) and, from an **MSYS** shell (not the
MINGW64 one), the toolchain and the build tools:

```sh
pacman -S --needed \
    make git unzip zip tar \
    cmake ninja \
    mingw-w64-x86_64-toolchain \
    mingw-w64-x86_64-cmake \
    mingw-w64-x86_64-ninja \
    mingw-w64-x86_64-pkgconf \
    mingw-w64-x86_64-nasm \
    bsdtar lzip
```

A few things are easy to get wrong here:

- **Both cmake and ninja packages are needed, and the MSYS ones have to win.**
  The bare `cmake`/`ninja` are the MSYS builds; the `mingw-w64-x86_64-` ones are
  native. The build writes MSYS paths (`/d/…`) into `koreader_vars.cmake` and
  into the compiler-probe scratch files, and only the MSYS builds resolve those.
  With the native ones, `CMAKE_MODULE_PATH` ends up empty — so every `include()`
  fails with "could not find requested file", an error that points at the
  includes rather than at cmake — and the probe fails with "missing and no known
  rule to make it". Keep `/usr/bin` ahead of `/mingw64/bin` in `PATH`.
- `bsdtar` (from `libarchive`) and `lzip` are needed to unpack some of the
  thirdparty archives; they are not part of the base install.
- `nasm` is needed by libjpeg-turbo's SIMD code.

## Getting the source

The Windows support is not upstream yet, so clone the fork — its `base`
submodule already points at the matching `koreader-base` fork:

```sh
git clone --branch win32-port https://github.com/yiuf63/koreader-windows.git
cd koreader-windows
git submodule update --init --recursive
```

To build on top of upstream instead, take the `win32: …` commits from that
branch; nothing else is needed.

## Building

```sh
export PATH="/usr/bin:/mingw64/bin:$PATH"
export MSYSTEM=MSYS
make TARGET=win32 -j"$(nproc)"
```

The first build takes a while: it compiles LuaJIT, MuPDF, crengine, DjVuLibre
and ~30 other libraries.

`make TARGET=win32` also accepts the usual `kodev`-style variables, but note
that `kodev` itself is a bash script that assumes a POSIX host; calling `make`
directly is the supported route here.

## Running

The launcher expects to run from the root of the build tree (it resolves
`libs/` and `common/` relative to its working directory), so:

```sh
make TARGET=win32 run
# or, equivalently:
cd koreader-win32-x86_64-w64-mingw32/koreader && ./koreader.exe
```

To open a document directly:

```sh
cd koreader-win32-x86_64-w64-mingw32/koreader && ./koreader.exe /path/to/book.epub
```

## Packaging

```sh
make TARGET=win32 update-zip
```

This dereferences the install tree and writes a self-contained
`koreader-win32-<machine>-<version>.zip` (~200MB, mostly the CJK fonts and the
OCR libraries). Unzip it anywhere and run `koreader.exe` — it does not need
MSYS2 on the target machine.

## How it fits together

The layout the launcher expects at runtime:

| Path | Contents |
|------|----------|
| `koreader.exe` | the launcher (`base/win_loader.c`) |
| `lua51.dll` | the LuaJIT runtime the launcher links against |
| `libs/` | shared libraries, loaded by `ffi.loadlib` |
| `common/` | Lua C extension modules, loaded by `require` |
| `frontend/`, `plugins/`, `reader.lua`, ... | the Lua sources |

A few details are Windows-specific and worth knowing about when debugging:

- **DLL search path.** PE has no soname mechanism (unlike ELF or Mach-O): a DLL
  records its dependencies by literal file name, and the loader resolves those
  from the executable's directory and the search path. `win_loader.c` therefore
  registers both `libs/` and `common/` via `AddDllDirectory`, and sets
  `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS |
  LOAD_LIBRARY_SEARCH_USER_DIRS)`. Without this, `libarchive-13.dll` cannot find
  the `libz.dll` sitting next to it.

- **DLL naming.** `libs/` holds two names for most libraries — the canonical
  `lib<name>-<version>.dll` that `ffi/loadlib.lua` asks for, and the original
  spelling that other DLLs import. Both are the same file (a hard link).
  See `base/thirdparty/cmake_modules/install_lib.sh`.

- **Symlinks.** MSYS2 emulates `ln -s` by *copying* unless asked otherwise, so
  `base/Makefile.defs` exports `MSYS=winsymlinks:nativestrict`. Without it the
  build tree silently goes stale: the copies under `build/` never pick up later
  edits to `base/ffi/`, and the build keeps installing the old Lua modules.

- **Line endings.** `core.autocrlf` is on by default on Windows, so
  thirdparty sources are checked out with CRLF while the patches are stored
  with LF. Patches are applied with `--ignore-whitespace` for that reason.

- **Patched submodules show up as dirty.** crengine is a submodule that is
  patched in place (there is no download step to unpack it into), so
  `git status` reports it as modified once built. That is expected: the patch is
  re-applied from its pristine state on every build, so
  `git submodule update --force` is always safe.

## Data directory

Configuration and caches live in `%APPDATA%\koreader`, not next to the
executable. Set `KO_HOME` to override this.

## Testing

`./kodev test front` does not work for this target: the harness drives `busted`
(which comes from luarocks and is only built for the emulator), and it runs the
specs under `luajit`, which exports none of the POSIX shims `koreader.exe`
provides — the frontend cannot even load there.

```sh
tools/win32/run_specs.sh
```

runs the suite one spec per process instead. That also contains the damage from
the handful of specs that drive the real document and framebuffer stack and
hard-crash the process: a crash costs one spec rather than the whole run.
Results land in `%TEMP%\kospecs_all.txt`, with per-spec output alongside.

Current state: 76 spec files, 596 assertions, 262 passing, 0 crashes. No
remaining failure is Windows-specific; they are specs that need the emulator
harness's fixtures (screen geometry, `spec/front/unit/data`) or parts of
luassert the runner does not implement.

## Limitations

- **Terminal plugin** — needs a Unix pseudoterminal (`/dev/ptmx`); ConPTY would
  be a different implementation. The plugin disables itself.
- **Time sync plugin** — needs `ntpd`/`ntpdate` and a Unix privileged-clock
  model. The plugin disables itself.
- **No `fork()`.** Document loading normally happens in a forked child so the UI
  can report progress. Windows has no `fork`, so `ffi/util.lua` reports it as
  unavailable and `ui/trapper.lua` runs the task inline. Loading a large
  document therefore blocks the UI for the duration, and there is no progress
  bar. `CreateProcess` is the obvious alternative, but the render path is not
  re-entrant: it mutates `m_pages`, the style caches and conNode geometry, and
  the draw path re-enters `partialRender`. Doing this properly needs a headless
  entry point and a private cache directory (the global `cr3cache.inx` would
  otherwise be shared) — it is not a drop-in swap.

### A note on rendering threads

crengine is built with `CR_USE_THREADS 0`, which makes every `LVLock` and
`CRENGINE_GUARD` a no-op. On top of that, rendering mutates shared document
state, so moving it to a thread would race with the UI thread's own draws rather
than merely interleave with them. Enabling threads here means auditing
crengine's locking, not just flipping a flag. Until then, rendering stays on the
UI thread.
