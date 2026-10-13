# KOReader for Windows

English | [中文](README.zh_CN.md)

A native Windows x64 build of [KOReader](https://koreader.rocks), built with
MinGW-w64 from MSYS2. It runs as a normal Windows application — there is **no
Cygwin, no WSL, and no POSIX emulation layer** — and nothing needs to be
installed on the target machine.

## Download and run

1. Get the latest `koreader-win32-x86_64-*.zip` from the
   [releases page](../../releases).
2. Unzip it anywhere (e.g. `D:\Apps\`). The zip contains a single `koreader\`
   folder; you can run it from wherever you unpacked it.
3. Run `koreader.exe` inside that folder.

To open a book directly, drag it onto `koreader.exe`, or:

```
koreader.exe D:\Books\some-book.epub
```

Requires **Windows 10 version 1903 or newer, 64-bit**. That 1903 requirement is
real rather than cautious: the build declares `activeCodePage=UTF-8` in its
application manifest, which is what lets non-ASCII paths work — a book named
`中文测试书名.epub`, or an installation under a user name with accents. Before
1903 that manifest field is ignored and such names arrive as mojibake.

There is **no 32-bit build**, and the name does not say so: `TARGET=win32` names
the platform, and the `mingw32` in the toolchain triplet (`x86_64-w64-mingw32`)
names the Win32 API, which the 32-bit toolchain shares (`i686-w64-mingw32`).
The architecture is the `x86_64` in the archive name, and every DLL in it is
64-bit. `tools/win32/check_arch.sh` reports this for a given build.

Settings, caches and reading history go to `%APPDATA%\koreader`, not next to the
executable. Set `KO_HOME` to put them elsewhere (useful for a portable install
on a USB stick).

### If something goes wrong

The build is a **console-subsystem** binary, so a console window appears while
it starts. That window is hidden automatically when you double-click the
executable, and kept visible when you launch it from a terminal — so you can
always see the log by starting it from `cmd` or PowerShell:

```
cd path\to\koreader
koreader.exe
```

If it is not starting, look in `%APPDATA%\koreader\crash.log`.

## What works

| | |
|---|---|
| **Formats** | EPUB, PDF, DjVu, TXT — all verified opening and rendering |
| **Re-layout on resize** | Yes; content reflows rather than stretching |
| **Interface** | All 48 bundled translations load, Chinese included |
| **Plugins** | Load and run |

## Known limitations

- **No `fork()`, so loading a document blocks the interface.** On other
  platforms loading happens in a forked child, which is also how the progress
  bar works. Windows has no `fork`, so the task runs inline: opening a large
  document freezes the UI for its duration, with no progress bar. `CreateProcess`
  is the obvious alternative, but the render path is not re-entrant — it mutates
  `m_pages`, the style caches and conNode geometry, and the draw path itself
  re-renders via `partialRender` — so doing it properly needs a headless entry
  point and a private cache directory (the global `cr3cache.inx` would otherwise
  be shared between processes). It is not a drop-in swap.
- **Cover extraction is likewise inline**, so the first visit to a large
  directory pauses while covers are generated. Afterwards they are cached.
- **No rendering threads.** crengine is built with `CR_USE_THREADS 0`, which
  turns every `LVLock`/`CRENGINE_GUARD` into a no-op, and rendering mutates
  shared document state that the UI thread also draws from. Enabling threads
  means auditing that locking, not flipping a flag.
- **Terminal plugin** — needs a Unix pseudoterminal (`/dev/ptmx`); ConPTY would
  be a different implementation. The plugin disables itself.
- **Time sync plugin** — needs `ntpd`/`ntpdate` and a Unix privileged-clock
  model. The plugin disables itself.

## Building it yourself

Windows support is not upstream yet, so clone this fork — its `base` submodule
already points at the matching `koreader-base` fork:

```sh
git clone --branch win32-port https://github.com/yiuf63/koreader-windows.git
cd koreader-windows
git submodule update --init --recursive
```

Then, from an **MSYS** shell (not the MINGW64 one):

```sh
export PATH="/usr/bin:/mingw64/bin:$PATH"
make TARGET=win32 -j4
```

`-j4` rather than `-j$(nproc)`: crengine has translation units that each peak
near 1 GB, and eight at once exhausts a 16 GB machine.

See [`doc/Building_Windows.md`](doc/Building_Windows.md) for prerequisites, the
runtime layout, and the Windows-specific details worth knowing when debugging.

> **Both cmake and ninja packages are needed, and the MSYS ones must win the
> `PATH` race.** The bare `cmake`/`ninja` are the MSYS builds; the
> `mingw-w64-x86_64-` ones are native. The build writes MSYS paths into
> `koreader_vars.cmake`, and only the MSYS builds resolve those — with the
> native ones, `CMAKE_MODULE_PATH` ends up empty and every `include()` fails
> with "could not find requested file", an error that points at the includes
> rather than at cmake.

### Testing

`./kodev test front` does not work for this target: the harness drives `busted`,
which comes from luarocks and is only built for the emulator, and it runs the
specs under `luajit`, which exports none of the POSIX shims `koreader.exe`
provides. Use instead:

```sh
tools/win32/run_specs.sh     # the frontend spec suite, one spec per process
tools/win32/ci_smoke.sh      # runtime smoke test (POSIX shim, DLLs, gettext)
tools/win32/check_dlls.sh    # every DLL's imports resolve
```

The suite runs one spec per process because a few specs drive the real document
and framebuffer stack and hard-crash the process; that way a crash costs one
spec rather than the whole run. Current state: **76 spec files, 596 assertions,
268 passing, 0 crashes**. No remaining failure is Windows-specific — they are
specs that need the emulator harness's fixtures (screen geometry, documents
under `spec/front/unit/data`) or parts of luassert the runner does not
implement.

## Architecture notes

### Why this is a `TARGET=win32` build, not a fork

The changes live in the regular build system and the platform layer, and are
shaped to be mergeable upstream. Nothing is a Windows-only rewrite of shared
code.

### How the pieces fit at runtime

| Path | Contents |
|------|----------|
| `koreader.exe` | the launcher (`base/win_loader.c`) |
| `lua51.dll` | the LuaJIT runtime the launcher links against |
| `libs/` | shared libraries, loaded by `ffi.loadlib` |
| `common/` | Lua C extension modules, loaded by `require` |
| `frontend/`, `plugins/`, `reader.lua`, … | the Lua sources |

Windows-specific details worth knowing:

- **DLL search path.** PE has no soname mechanism, unlike ELF or Mach-O: a DLL
  records its dependencies by literal file name, and the loader resolves those
  from the executable's directory and the search path. `win_loader.c` therefore
  registers `libs/` and `common/` via `AddDllDirectory`. Without it,
  `libarchive-13.dll` cannot find the `libz.dll` sitting next to it.

- **POSIX symbols.** MSVCRT exports only the underscore-prefixed spellings
  (`_open`, not `open`), while the Lua code calls the POSIX ones. `ffi.C`
  resolves against the process image and its import table, so `win32_posix.c`
  exports wrappers from `koreader.exe` itself, and every call site resolves with
  no Lua changes. Those wrappers also force binary mode: the CRT opens files in
  *text* mode by default, which rewrites CRLF and silently shortens reads — that
  is what stopped translation catalogues (`.mo`, binary) from loading.

- **DLL naming.** `libs/` holds two names for most libraries — the canonical
  `lib<name>-<version>.dll` that `ffi/loadlib.lua` asks for, and the original
  spelling that other DLLs import. They are the same file (a hard link). See
  `base/thirdparty/cmake_modules/install_lib.sh`.

- **Symlinks.** MSYS2 emulates `ln -s` by *copying* unless told otherwise, so
  `base/Makefile.defs` sets `MSYS=winsymlinks:nativestrict`. Without it the
  build tree silently goes stale: copies under `build/` never pick up later
  edits to `base/ffi/`.

- **Line endings.** `core.autocrlf` is on by default on Windows, so thirdparty
  sources are checked out with CRLF while patches are stored with LF. Patches
  are applied with `--ignore-whitespace` for that reason.

- **Patched submodules show up as dirty.** crengine is a submodule patched in
  place, so `git status` reports it modified after a build. The patch is
  re-applied from pristine state each time, so `git submodule update --force` is
  always safe.

## Relationship to upstream

This is an unofficial port. Upstream KOReader does not ship a Windows build, and
this repository is not affiliated with the KOReader project. The application
itself is the same KOReader, licensed AGPL-3.0 — see [COPYING](COPYING).

If you are looking for KOReader generally, start at
[github.com/koreader/koreader](https://github.com/koreader/koreader).
