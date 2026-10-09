# AGENTS.md

## Language & Runtime

KOReader is written in **Lua** targeting **LuaJIT** (not standard Lua 5.1). The C/C++ layer lives in `base/` (a git submodule: `koreader-base`).

## Developer CLI

All build/test/run commands go through `./kodev` (requires bash >= 4.0). Run `./kodev activate` to add it to `$PATH`.

```bash
./kodev build                 # build emulator (debug by default)
./kodev run                   # run emulator
./kodev test front            # run frontend unit tests
./kodev test front readerbookmark_spec.lua  # run a single test
./kodev test base             # run base unit tests
make static-check             # luacheck lint only
./kodev check                 # full lint: shellcheck + luacheck + tab/unscaled-size checks
./kodev fetch-thirdparty      # init/update git submodules
```

Build is sequential: `base` must build first, then the frontend. The `Makefile` handles this.

## Code Style

- **Indent**: 4 spaces (Lua), tabs in Makefiles. No tabs in `.lua` files.
- **Line endings**: LF everywhere.
- **TODO format**: `--- @todo`, `--- @fixme`, `--- @warning` (must be tagged with `---` prefix).
- **Lint config**: `.luacheckrc` (globals, ignores). CI also checks for unscaled pixel sizes — use `ui.size` constants, not raw numbers.

## Architecture

| Path | Purpose |
|------|---------|
| `reader.lua` | Main entry point |
| `frontend/` | Core app: UI widgets, document handling, device abstraction |
| `plugins/*.koplugin/` | Plugin directory (each plugin is a folder) |
| `base/` | `koreader-base` submodule (LuaJIT, C libs, native build) |
| `spec/unit/` | Unit tests (busted framework) |
| `test/` | Test data/fixtures |
| `l10n/` | Translations (Weblate submodule) |
| `platform/` | Platform-specific launchers and packaging |
| `make/` | Makefile fragments per target |
| `tools/` | Dev helper scripts |
| `doc/` | Developer documentation |

## Key Files

- `setupkoenv.lua` — Lua/FFI search path setup (loaded before anything else)
- `datastorage.lua` — data directory resolution
- `defaults.lua` — default settings
- `frontend/device.lua` — device abstraction layer
- `frontend/pluginloader.lua` — plugin discovery and loading

## Globals

Two globals are loaded early and used everywhere: `G_reader_settings` (user settings) and `G_defaults` (default settings). These are defined in `.luacheckrc`.

## Testing

Tests use [busted](https://olivinelabs.com/busted/) and run inside KOReader's LuaJIT environment. Test files live in `spec/unit/*_spec.lua`.

```bash
./kodev test front                        # all frontend tests
./kodev test front document_spec.lua      # single test file
```

Coverage: `./kodev cov` (runs front tests with luacov).

## Build Targets

The `TARGET` variable selects the platform. Default is `emulator`. Other targets: `kindle`, `kobo`, `android-arm64`, `pocketbook`, `remarkable`, `macos`, `linux`, etc. See `./kodev build --help` for the full list.

For cross-compilation, the build system expects the appropriate toolchains. See `doc/Building.md` for per-platform prerequisites.

## Gotchas

- Submodules must be fetched before building: `./kodev fetch-thirdparty` (auto-runs if detected missing).
- The `base/` directory is a separate repo. Changes there require rebuilding base first.
- Emulator builds default to debug (`KODEBUG=1`). Release builds omit debug symbols.
- The CI check script (`.ci/check.sh`) runs shellcheck, luacheck, tab detection, and unscaled-size detection — all of which must pass.
