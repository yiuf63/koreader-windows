# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **KOReader for Windows** — a native Windows x64 port of KOReader, a document viewer primarily aimed at e-ink readers. This is the `win32-port` branch that builds a native `koreader.exe` with **no POSIX emulation layer** (no Cygwin/WSL/MSYS2 required at runtime).

- **Language**: Lua (targeting LuaJIT, not standard Lua 5.1)
- **Build System**: GNU Make + bash scripts (requires MSYS2 bash >= 4.0 for development)
- **Current Branch**: `win32-port` (not upstream; this is an unofficial port)
- **Architecture**: Changes are scoped to build system, `base/`, and platform-specific parts — shaped to be mergeable upstream

## Essential Commands

```bash
# Build (from MSYS shell, not MINGW64)
export PATH="/usr/bin:/mingw64/bin:$PATH"
make TARGET=win32 -j4              # Use -j4, not -j$(nproc): crengine peaks ~1GB per TU

# Emulator (for quick testing; uses SDL)
./kodev build                      # builds emulator (debug by default)
./kodev run                        # runs emulator

# Testing
./kodev test front                               # all frontend tests (emulator only)
./kodev test front readerbookmark_spec.lua       # single test (emulator only)
tools/win32/run_specs.sh                         # win32: frontend specs, one per process
tools/win32/ci_smoke.sh                          # win32: runtime smoke test
tools/win32/check_dlls.sh                        # win32: verify DLL imports resolve

# Linting
make static-check                  # luacheck only
./kodev check                      # full: shellcheck + luacheck + tabs + unscaled-size

# Submodules
./kodev fetch-thirdparty           # init/update submodules (auto-runs if missing)
```

## Windows-Specific Build Notes

1. **Both cmake and ninja packages needed**: MSYS ones must win the PATH race. Bare `cmake`/`ninja` are MSYS builds; `mingw-w64-x86_64-cmake` are native. Build writes MSYS paths that only MSYS builds resolve.

2. **No `./kodev test front` on win32**: busted comes from luarocks and only works for emulator. Use `tools/win32/run_specs.sh` instead (runs one spec per process to isolate crashes).

3. **Symlinks**: `base/Makefile.defs` sets `MSYS=winsymlinks:nativestrict` to avoid MSYS2 copying files instead of symlinking.

4. **Line endings**: `core.autocrlf` on by default; patches applied with `--ignore-whitespace`.

5. **Submodules show dirty after build**: crengine is patched in-place. `git submodule update --force` is always safe.

## Architecture

### Directory Structure

```
reader.lua              # Main entry point (invokes setupkoenv.lua first)
setupkoenv.lua          # Lua/FFI search path setup (loaded before everything)
datastorage.lua         # Data directory resolution
defaults.lua            # Default settings
base/                   # koreader-base submodule (C/C++ layer, LuaJIT, native libs)
frontend/               # Core app layer
  ├── device.lua        # Device abstraction entry point
  ├── device/           # Per-platform device implementations
  ├── apps/             # Two apps: filemanager/ and reader/
  │   └── reader/       # Reader app (readerui.lua + modules/)
  ├── document/         # Document handling (PDF, EPUB, DjVu, etc.)
  └── ui/               # UI widgets and framework
plugins/*.koplugin/     # Plugins (each is a directory with _meta.lua + main.lua)
platform/               # Platform-specific launchers and packaging
  ├── common/           # Shared platform code
  └── win32/            # Windows launcher (not in upstream yet)
l10n/                   # Translations (Weblate submodule)
spec/unit/              # Unit tests (busted framework)
doc/                    # Developer documentation
```

### Key Concepts

**Two Global Settings Objects** (defined in `.luacheckrc`):
- `G_reader_settings` — user settings (from `settings.reader.lua`)
- `G_defaults` — default settings (from `defaults.lua`)

**Plugin Discovery**: `frontend/pluginloader.lua` scans `plugins/*.koplugin/` directories. Each plugin has:
- `_meta.lua` — metadata
- `main.lua` — implementation

**Device Abstraction**: `frontend/device.lua` loads platform-specific device implementation from `frontend/device/<platform>/device.lua`. Each platform provides its own `device.lua` and `powerd.lua`.

**Two Apps**: KOReader has two main apps in `frontend/apps/`:
- `filemanager/` — file browser
- `reader/` — document reader (main UI is `readerui.lua`)

### Windows Runtime Layout

```
koreader.exe            # Launcher (base/win_loader.c) + POSIX shims (win32_posix.c)
lua51.dll               # LuaJIT runtime
libs/                   # Shared libraries (loaded by ffi.loadlib)
common/                 # Lua C extension modules (loaded by require)
frontend/, plugins/     # Lua sources
```

**Key Windows Implementation Details**:
- **No fork()**: Document loading blocks UI (no progress bar). Cover extraction also inline.
- **DLL search path**: `win_loader.c` registers `libs/` and `common/` via `AddDllDirectory`.
- **POSIX symbols**: `win32_posix.c` exports wrappers from `koreader.exe` so `ffi.C` calls resolve without Lua changes.
- **DLL naming**: All libraries use canonical `lib<name>-<version>.dll`. Import archives rewritten via `record_canonical_implib.sh` before linking.
- **Settings location**: `%APPDATA%\koreader` (not next to exe). Override with `KO_HOME` env var.

## Code Style

- **Indent**: 4 spaces in Lua, tabs in Makefiles
- **Line endings**: LF everywhere
- **No tabs in `.lua` files**: CI will fail
- **TODO format**: Use `--- @todo`, `--- @fixme`, `--- @warning` (must have `---` prefix)
- **Unscaled sizes**: Use `ui.size` constants, not raw pixel values. CI checks for violations.
- **Lint config**: `.luacheckrc` defines globals and ignores

## Testing

Tests use [busted](https://olivinelabs.com/busted/) and run in KOReader's LuaJIT environment. Test files: `spec/unit/*_spec.lua`.

**Important**: Some specs drive real document/framebuffer stack and can crash. Windows runner isolates this (one spec per process).

## Build System

- **Sequential build**: `base/` must build first, then frontend. `Makefile` handles this.
- **Target selection**: `TARGET` variable selects platform (default: `emulator`). Others: `win32`, `kindle`, `kobo`, `android-arm64`, `pocketbook`, `remarkable`, etc.
- **Debug builds**: Emulator defaults to debug (`KODEBUG=1`). Release builds omit debug symbols.
- **Submodule**: `base/` is separate repo. Changes there require rebuilding base first.

## Windows-Specific Limitations

- **No fork()**: Document loading and cover extraction block UI
- **No rendering threads**: crengine built with `CR_USE_THREADS 0` (locking not audited)
- **Terminal plugin disabled**: needs Unix PTY (`/dev/ptmx`); ConPTY would be different impl
- **Time sync plugin disabled**: needs `ntpd`/`ntpdate` and Unix privileged-clock model

## Merging Upstream

This branch is shaped to be mergeable but has two deliberate differences:
1. `.gitmodules` points at `koreader-base` fork (must revert to upstream URL in PR)
2. Both CI workflows kept (upstream's `build.yml` + this branch's `windows.yml`)

All Windows changes are scoped: import rewriting in `WIN32` blocks, tesseract changes behind `$<BOOL:${WIN32}>`, Makefile additions in `CURRENT_OS` branches.
