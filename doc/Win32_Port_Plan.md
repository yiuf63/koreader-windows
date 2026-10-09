# KOReader Windows 移植计划

## 现状评估

### 已有的 Windows 支持（上游已实现）

**FFI 绑定层（`base/ffi/`）— 大部分已适配**：

| 文件 | Windows 支持 | DLL 名称 |
|------|-------------|----------|
| `util.lua` | ✅ `gettime`, `sleep`, `realpath`, `basename`, `dirname`, `multiByteToUTF8`, `isWindows` | — |
| `freetype.lua` | ✅ | `libs/libfreetype-6.dll` |
| `mupdf.lua` | ✅（但 `wrap-mupdf.so` 未适配） | `libs/libmupdf.dll` |
| `jpeg.lua` | ✅ | `libs/libturbojpeg.dll` |
| `png.lua` | ✅ | `libs/liblodepng.dll` |
| `zlib.lua` | ✅ | `libs/libz1.dll` |
| `zstd.lua` | ✅ | `libs/libzstd.dll` |
| `utf8proc.lua` | ✅ | `libs/libutf8proc-2.dll` |
| `koptcontext.lua` | ✅ | `libs/liblept-5.dll`, `libs/libk2pdfopt-2.dll` |
| `pic.lua` | ✅ | `libs/libgif-7.dll` |
| `posix_h.lua` | ✅ MinGW 兼容（第 569-588 行） | — |

**SDL2 路径**：
- `base/ffi/input_SDL2_0.lua` — 跨平台输入，Windows 可直接用
- `base/ffi/framebuffer_SDL2_0.lua` — 跨平台帧缓冲，Windows 可直接用
- `base/ffi/SDL2_0.lua` — SDL2 加载，Windows 候选列表包含 `SDL2`

**构建系统（`base/Makefile.defs`）**：
- `TARGET=win32` 分支已存在（第 164 行）
- 工具链：`x86_64-w64-mingw32`
- `Makefile.third` 有 16 处 WIN32 条件判断

### 需要修复的问题

| # | 问题 | 文件 | 难度 |
|---|------|------|------|
| 1 | `wrap-mupdf.so` 硬编码 `.so` 扩展名 | `base/ffi/mupdf.lua:27` | ⭐ |
| 2 | `setupkoenv.lua` require 不存在的 `ffi/loadlib` | `setupkoenv.lua:9` | ⭐ |
| 3 | SDL 设备的 `setDateTime` 用 Linux `date`/`hwclock` | `frontend/device/sdl/device.lua:376-390` | ⭐⭐ |
| 4 | SDL 设备的 `isConnected` 用 Linux `ping` | `frontend/device/sdl/device.lua:440-453` | ⭐⭐ |
| 5 | `font_settings.lua` 无 Windows 字体路径 | `frontend/ui/elements/font_settings.lua:28-36` | ⭐⭐ |
| 6 | `datastorage.lua` 无 Windows 数据目录 | `datastorage.lua:41-42` | ⭐ |
| 7 | 第三方库 MinGW 编译验证 | `base/thirdparty/*` | ⭐⭐⭐⭐ |
| 8 | `libwrap-mupdf` 需要编译为 `.dll` | `base/wrap-mupdf.c` | ⭐⭐⭐ |

---

## 分阶段执行计划

### 阶段 1：基础修复（Lua 层，无需编译）

目标：修复所有 Lua 层的 Windows 兼容性问题，使代码逻辑在 Windows 上正确运行。

#### 1.1 修复 `mupdf.lua` 的 wrap-mupdf 加载
- **文件**：`base/ffi/mupdf.lua:27`
- **改动**：`ffi.load("libs/libwrap-mupdf.so")` → 根据 `ffi.os` 选择 `.so` 或 `.dll`

#### 1.2 修复 `setupkoenv.lua` 的 loadlib 引用
- **文件**：`setupkoenv.lua:9`
- **问题**：`require("ffi/loadlib")` 引用不存在的文件
- **改动**：确认此文件用途。如果只是 DLL 加载辅助，在 Windows 上用 `ffi.load` 直接加载即可。可能需要创建 `base/ffi/loadlib.lua` 或移除此 require。

#### 1.3 修复 `datastorage.lua` 的 Windows 数据目录
- **文件**：`datastorage.lua`
- **改动**：在 `else` 分支前添加 Windows 检测，使用 `%APPDATA%/koreader`

#### 1.4 修复 `font_settings.lua` 的 Windows 字体路径
- **文件**：`frontend/ui/elements/font_settings.lua`
- **改动**：在 `getDir` 函数中添加 `jit.os == "Windows"` 分支，返回 `C:/Windows/Fonts`

#### 1.5 修复 SDL 设备的 Linux 命令
- **文件**：`frontend/device/sdl/device.lua`
- **改动**：
  - `setDateTime`（第 376 行）：Windows 上用 Win32 API 或 stub
  - `isConnected`（第 440 行）：Windows 上用 `ping -n 1` 语法
  - `isCommand`（第 29 行）：Windows 上用 `where` 替代 `command -v`
  - `getLinkOpener`（第 47 行）：Windows 上用 `start`

### 阶段 2：构建环境搭建

目标：在 MSYS2 环境中验证 MinGW 编译。

#### 2.1 安装 MSYS2 + MinGW-w64 工具链
```bash
pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake
```

#### 2.2 尝试 `make TARGET=win32`
- 记录哪些第三方库编译失败
- 逐个修复编译问题

#### 2.3 编译 `libwrap-mupdf.dll`
- `base/wrap-mupdf.c` 需要用 MinGW 编译为 DLL

### 阶段 3：集成测试

目标：生成可运行的 `koreader.exe`，验证基本功能。

#### 3.1 链接所有库生成 exe
#### 3.2 收集运行时 DLL
#### 3.3 验证启动、打开 PDF、翻页等基本功能

---

## 阶段 1 完成（Lua 层修复）

### 已完成的修复

| # | 修复 | 文件 |
|---|------|------|
| 1 | `wrap-mupdf.so` 加载改为跨平台（`.so`/`.dll`/`.dylib`） | `base/ffi/mupdf.lua:27` |
| 2 | `.dll` 优先加载；`ffi/loadlib` 改为 `pcall` 可选 | `setupkoenv.lua` |
| 3 | Windows 数据目录 `%APPDATA%/koreader`；`getFullDataDir` 支持盘符 | `datastorage.lua` |
| 4 | Windows 字体路径 `C:/Windows/Fonts` | `frontend/ui/elements/font_settings.lua` |
| 5 | `isCommand` 用 `where`；`getLinkOpener` 用 `start`；`setDateTime` stub；`ping -n 1` 语法 | `frontend/device/sdl/device.lua` |
| 6 | `getDefaultRoute` 用 `ipconfig` 获取网关 | `frontend/device/generic/device.lua` |
| 7 | `Makefile.defs` WIN32 下不加载 `origin.ldflags` | `base/Makefile.defs:550` |

## 阶段 2 进度（构建环境）

### 已验证

- MSYS2 MinGW-w64 工具链可用（`x86_64-w64-mingw32-gcc` 16.1.0）
- `windres` 符号链接已创建
- Make 的 `TARGET=win32` 正确识别工具链
- LDFLAGS 已正确（无 `origin.ldflags`）

### 未解决的问题

**CMake 编译器测试失败**：`Cannot create temporary file in C:\WINDOWS\: Permission denied`

- 原因：CMake 通过 `cmd.exe` 执行 MinGW 编译器，`cmd.exe` 无法继承 MSYS2 的 `TEMP`/`TMP` 环境变量
- MinGW 链接器找不到可写的临时目录
- **需要在 MSYS2 MinGW 64 终端中直接运行** `make TARGET=win32`，而不是在 Git Bash 中

### 下一步

**必须在 MSYS2 MinGW 64 终端中运行**（开始菜单 → MSYS2 MinGW 64-bit）：

```bash
cd /d/Code/koreader/base
make TARGET=win32 -j4
```

原因：
1. Git Bash 的 `cmd.exe` 子进程无法继承 MSYS2 的 `TEMP`/`TMP` 路径
2. MSYS2 MinGW 64 终端的环境变量与 `cmd.exe` 兼容
3. 需要网络访问来下载 LuaJIT 源码（CMake ExternalProject）
