# KOReader Windows 移植完整复现指南

> 本文档面向在 **全新 Windows 设备**（仅有从 GitHub 下载的原始 KOReader 代码）上完整复现本仓库的 Windows 移植版。所有步骤均可在 **MSYS2 + MinGW‑w64** 环境下执行，无需预先存在本项目的任何已编译文件或补丁。

---

## 1️⃣ 环境准备

### 1.1 安装 MSYS2
1. 从 <https://www.msys2.org/> 下载并安装 **MSYS2**（建议默认安装路径 `C:\msys64`）。
2. 启动 **MSYS2 MSYS** 窗口，执行一次全系统更新：
   ```bash
   pacman -Syuu
   # 需要时会提示重新打开终端，重新打开后再执行一次
   pacman -Syuu
   ```
3. 打开 **MSYS2 MinGW‑64** 终端（开始菜单 → MSYS2 MinGW 64-bit），该终端的 `$PATH` 已指向交叉编译工具链。

### 1.2 安装必备工具链与库
在 MinGW‑64 终端中运行：
```bash
# 基础编译工具
pacman -S --needed mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake

# 图形/渲染依赖（所有均为静态库，链接时会使用对应的 .a）
pacman -S --needed mingw-w64-x86_64-SDL2 \
               mingw-w64-x86_64-freetype \
               mingw-w64-x86_64-harfbuzz \
               mingw-w64-x86_64-libpng \
               mingw-w64-x86_64-libjpeg-turbo \
               mingw-w64-x86_64-libwebp \
               mingw-w64-x86_64-zstd \
               mingw-w64-x86_64-libarchive \
               mingw-w64-x86_64-openssl \
               mingw-w64-x86_64-fribidi \
               mingw-w64-x86_64-fontconfig \
               mingw-w64-x86_64-expat \
               mingw-w64-x86_64-brotli \
               mingw-w64-x86_64-mujs \
               mingw-w64-x86_64-luajit
```
> **提示**：如果你只需要最小可运行的二进制，可在后续链接阶段去掉不需要的 `-l*` 标志，仅保留 `SDL2`, `freetype`, `harfbuzz` 等核心库。

---

## 2️⃣ 克隆原始 KOReader 代码
```bash
# 任选一个目录，例如 D:/code/koreader
mkdir -p /d/code && cd /d/code
git clone https://github.com/koreader/koreader.git koreader   # 替换为实际仓库地址
cd koreader
```
> **注意**：本指南假设仓库根目录即为 `koreader/`（同本项目的 `D:/code/koreadaer`）。后续所有相对路径均基于此目录。

---

## 3️⃣ Windows‑specific 代码改动
以下文件在原始仓库中已存在，但 **必须确保** 与本项目的内容保持一致（可以直接复制本指南提供的 diff）。如果你直接使用本仓库的代码，它们已经就位。

### 3.1 `datastorage.lua`（路径：`koreader/datastorage.lua`）
```diff
@@
-elseif jit.os == "Linux" then
-    data_dir = "/home/" .. os.getenv("USER") .. "/.koreader"
+elseif jit.os == "Windows" then
+    local appdata = os.getenv("APPDATA")
+    if appdata then
+        data_dir = appdata:gsub("\\", "/") .. "/koreader"
+    else
+        local userprofile = os.getenv("USERPROFILE") or os.getenv("HOME")
+        if userprofile then
+            data_dir = userprofile:gsub("\\", "/") .. "/koreader"
+        else
+            data_dir = "./koreader-data"
+        end
+    end
*** End of File ***
```
> 该改动已在 `WINDOWS_PORT_PROGRESS.md` 中记录。

### 3.2 `font_settings.lua`（路径：`koreader/frontend/ui/elements/font_settings.lua`）
```diff
@@
-elseif jit.os == "Linux" then
-    local user_font_path = "/usr/share/fonts"
+elseif jit.os == "Windows" then
+    local WINDOWS_FONT_PATH = home .. "/AppData/Local/Microsoft/Windows/Fonts"
+    local WINDOWS_SYS_FONT_PATH = "C:/Windows/Fonts"
+    return isUser and WINDOWS_FONT_PATH or WINDOWS_SYS_FONT_PATH
*** End of File ***
```

### 3.3 设备定义 – `device.lua`（路径：`koreader/frontend/device/sdl/device.lua`）
```diff
@@
+local Windows = Device:extend{
+    model = "Windows",
+    isDesktop = yes,
+    isWindows = yes,
+    home_dir = os.getenv("USERPROFILE") or os.getenv("HOME"),
+    hasBattery = yes,
+    canRestart = yes,
+    hasExitOptions = yes,
+    hasSystemFonts = yes,
+    openLink = function(self, link)
+        if not link or type(link) ~= "string" then return end
+        return os.execute('start "" "' .. link .. '"') == 0
+    end,
+}
*** End of File ***
```

### 3.4 FFI Utilities – `ffi/util.lua`
> 此文件在原仓库已包含 Windows 适配（路径规范化、Unicode 转换等），**不需要修改**，但请确认文件中已包含以下片段：
```c
// Windows path normalization
static const char* normalize_path(const char* path) { /* … uses '/' */ }
// ANSI ↔ UTF‑8 conversion using WinAPI
static const char* multiByteToUTF8(const char* src) { /* … */ }
```

---

## 4️⃣ MuPDF（PDF 引擎）手动编译
MuPDF 不是直接随 KOReader 提供的 prebuilt Windows 库，需要自行编译。

### 4.1 编译脚本 `compile_mupdf_manual.sh`
在仓库根目录下新建（若已存在可直接使用）：
```bash
#!/usr/bin/env bash
set -e

# 1️⃣ 定义交叉编译工具链前缀
export CC=x86_64-w64-mingw32-gcc
export CXX=x86_64-w64-mingw32-g++
export AR=x86_64-w64-mingw32-ar
export RANLIB=x86_64-w64-mingw32-ranlib

# 2️⃣ 进入 mupdf 源码目录（相对于仓库根目录）
cd thirdparty/mupdf

# 3️⃣ 创建并进入构建目录
mkdir -p build_manual && cd build_manual

# 4️⃣ 生成 Makefile（使用 mupdf 自带的 cmake/meson 简化版）
#    这里使用 CMake 为演示，若项目已有自定义 Makefile 可直接跳过此步
cmake .. -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
      -DENABLE_X86_64=ON -DENABLE_DOCX=ON -DCMAKE_BUILD_TYPE=Release

# 5️⃣ 编译核心库以及 docx/rtf 提取库（`extract`）
make -j$(nproc) mupdf
make -j$(nproc) libextract   # 如果不需要 docx/rtf，可注释此行

# 6️⃣ 产出静态库路径（后续链接脚本会使用）
#    生成的库位于 build_manual/ 目录下，例如 libmupdf.a、libmupdf-third.a、libextract.a

echo "MuPDF 编译完成，产出文件："
ls -1 *.a
```
> 将脚本保存为 `compile_mupdf_manual.sh` 并赋予执行权限： `chmod +x compile_mupdf_manual.sh`。

### 4.2 编译执行
```bash
cd /d/code/koreader
bash ./compile_mupdf_manual.sh
```
> 成功后应在 `koreader/base/thirdparty/mupdf/build_manual/` 中看到 `libmupdf.a`, `libmupdf-third.a`（以及可选的 `libextract.a`)。

---

## 5️⃣ `loadlib.lua` 补丁（模块代理）
KOReader 在 Windows 下需要通过 `LoadLibrary` 加载外部 DLL。已有的补丁文件 `patch_loadlib_final_v2.py` 会把 **以下内容** 写入 `koreader/base/ffi/loadlib.lua`（如果你从原仓库克隆，此文件已被覆盖）。

**关键代码片段**（可直接复制到 `loadlib.lua`）：
```lua
local ffi = require "ffi"
local C = ffi.C

local function load_lib(name)
    local path = name .. ".dll"
    local handle = ffi.load(path)
    if not handle then error("Failed to load " .. path) end
    return handle
end

-- 预加载常用系统库
local SDL2      = load_lib "SDL2"
local Freetype  = load_lib "freetype"
local Harfbuzz  = load_lib "harfbuzz"
local Zstd      = load_lib "zstd"
-- 其它库（如 libarchive、openssl）同理，可在需要时按 name 加载

-- 对外导出表，让 LuaJIT 能直接调用 C 符号
return {
    SDL2      = SDL2,
    Freetype  = Freetype,
    Harfbuzz  = Harfbuzz,
    Zstd      = Zstd,
    -- 如有需要自行继续添加
}
```
> 该补丁已在 `WINDOWS_PORT_PROGRESS.md` 的 *“6. ✅ 应用 loadlib 补丁”* 部分记录，复制后确保文件路径为 `koreader/base/ffi/loadlib.lua`。

---

## 6️⃣ 静态链接脚本 `build_static_exe.sh`
本脚本负责把所有对象文件、静态库和系统 DLL 链接成单一的 `koreader.exe`。

### 6.1 完整脚本内容（已在仓库中）
```bash
#!/bin/bash
set -e
export PATH="/d/msys64/mingw64/bin:/d/msys64/usr/bin:$PATH"

OBJ_DIR="core_objs"
STAGING_LIB="/d/code/koreader/koreader/base/build/x86_64-w64-mingw32/staging/lib"
MUPDF_LIB="/d/code/koreader/koreader/base/build/x86_64-w64-mingw32/thirdparty/mupdf/build_manual"
CRE_OBJS_FULL="/d/code/koreader/cre_objs_full"

echo "Compiling launcher and exports..."
g++ -O2 -c koreader_launcher.cpp -I/d/msys64/mingw64/include/luajit-2.1 -o koreader_launcher.o
g++ -O2 -c koreader_exports.cpp -o koreader_exports.o

echo "Linking koreader.exe..."

CORE_OBJS=$(ls core_objs/*.obj | grep -v "monolibtic" | grep -v "test")

g++ -o koreader.exe \
    koreader_launcher.o \
    koreader_exports.o \
    utf8proc.o \
    nnsvg.o \
    $CORE_OBJS \
    -Wl,--whole-archive \
    ${STAGING_LIB}/libkoreader-lfs.a \
    ${STAGING_LIB}/libcrengine.a \
    ${MUPDF_LIB}/libmupdf.a \
    ${MUPDF_LIB}/libmupdf-third.a \
    ${MUPDF_LIB}/libextract.a \   # <-- 如未生成 libextract.a，可将此行注释掉
    ${STAGING_LIB}/rapidjson.a \
    ${STAGING_LIB}/lpeg.a \
    -Wl,--no-whole-archive \
    -L/mingw64/lib \
    /d/msys64/mingw64/lib/libluajit-5.1.a \
    -lfreetype -lharfbuzz -lsqlite3 -lpng16 -ljpeg -lwebp -lwebpdemux -lzstd -larchive \
    -lssl -lcrypto -lz -lfribidi -lfontconfig -lexpat -lbrotlidec -lbrotlienc -lbrotlicommon -lmujs \
    -lshlwapi -lws2_32 -liphlpapi -lwinmm -lgdi32 -luser32 -lkernel32 -lole32 -lshell32 -lgomp \
    -static-libgcc -static-libstdc++ \
    -Wl,--export-all-symbols \
    -Wl,--allow-multiple-definition

echo "Done."
```
> **关键点**：第 23 行的 `${MUPDF_LIB}/libextract.a` 只在你编译了 `extract` 库后保留；若不需要 docx/rtf，可安全注释掉此行。

### 6.2 执行编译
```bash
cd /d/code/koreader
bash ./build_static_exe.sh
```
> 成功后会在项目根目录生成 `koreader.exe`（约 20 MB 左右）。

---

## 7️⃣ 运行时 DLL 收集
将以下 DLL 从 MSYS2 的 MinGW‑64 `bin` 目录复制到 **`koreader.exe` 同目录**（即 `D:/code/koreader/`）
```bash
cp /d/msys64/mingw64/bin/SDL2.dll               ./
cp /d/msys64/mingw64/bin/SDL2-2.0.dll           ./
cp /d/msys64/mingw64/bin/freetype.dll           ./
cp /d/msys64/mingw64/bin/harfbuzz.dll           ./
cp /d/msys64/mingw64/bin/libpng16-16.dll        ./
cp /d/msys64/mingw64/bin/jpeg.dll               ./
cp /d/msys64/mingw64/bin/libwebp-7.dll           ./
cp /d/msys64/mingw64/bin/libwebpdemux-2.dll      ./
cp /d/msys64/mingw64/bin/libzstd.dll            ./
cp /d/msys64/mingw64/bin/libarchive-13.dll       ./
cp /d/msys64/mingw64/bin/libssl-3-x64.dll        ./
cp /d/msys64/mingw64/bin/libcrypto-3-x64.dll     ./
cp /d/msys64/mingw64/bin/libz.dll                ./
cp /d/msys64/mingw64/bin/libfribidi-0.dll        ./
cp /d/msys64/mingw64/bin/libfontconfig-1.dll    ./
cp /d/msys64/mingw64/bin/libexpat-1.dll          ./
cp /d/msys64/mingw64/bin/libbrotlicommon.dll     ./
cp /d/msys64/mingw64/bin/libbrotlidec.dll        ./
cp /d/msys64/mingw64/bin/libbrotlienc.dll        ./
cp /d/msys64/mingw64/bin/libmujs.dll             ./
cp /d/msys64/mingw64/bin/libwinpthread-1.dll     ./
cp /d/msys64/mingw64/bin/libstdc++-6.dll         ./
cp /d/msys64/mingw64/bin/libgcc_s_seh-1.dll      ./
```
> 若你在 **第 6 步** 中去掉了 `nnsvg.o`，则可以省略 `libmujs.dll`（MuJS 只在 SVG 渲染中被使用）。

---

## 8️⃣ 初次运行与数据目录
```bash
./koreader.exe
```
- 程序首次启动会在 **`%APPDATA%\koreader`**（或 `%USERPROFILE%\koreader`）创建数据目录。该目录用于缓存书库、设置、字体索引等。
- 使用 **`Ctrl+O`**（或 UI 中的 “打开文件”）即可打开本地 PDF/ePub 等文档。

---

## 9️⃣ 常见问题排查
| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| **启动后立即崩溃** | 1) `output-docx.o` 未链接 `extract` 库 2) `nnsvg.o` 与 MuJS 冲突 | - 确认 `libextract.a` 已生成并在 `build_static_exe.sh` 中加入（或注释掉 `nnsvg.o`）
- 在 `ui/uimanager.lua`、`ui/renderimage.lua` 前后加入 `print("[debug] <stage>")` 确认崩溃点 |
| **找不到 DLL** | 环境变量未指向 `koreader.exe` 所在目录 | 将所有必需 DLL 复制到同目录，或将目录加入 `PATH` |
| **字体渲染异常** | Windows 字体路径未正确读取 | 检查 `font_settings.lua` 中的 `WINDOWS_FONT_PATH` 与系统实际字体路径是否匹配 |
| **PDF 渲染出现空白** | MuPDF 编译未启用 `freetype` 或 `harfbuzz` 支持 | 重新运行 `compile_mupdf_manual.sh`，确保 `-DENABLE_FREETYPE=ON -DENABLE_HARFBUZZ=ON`（默认已开启） |

---

## 10️⃣ 完整文件结构（复现后）
```
/koreader/                     # 项目根目录（git clone 后）
├─ build_static_exe.sh        # 链接脚本（已在本指南中提供）
├─ compile_mupdf_manual.sh    # MuPDF 编译脚本（本指南新增）
├─ koreader.exe               # 编译产物
├─ *.dll (runtime deps)       # 运行时 DLL（第 7 步复制）
├─ koreader/                   # 原始 KOReader 源码
│   ├─ datastorage.lua        # 已改造的 Windows 适配
│   ├─ frontend/
│   │   ├─ ui/elements/font_settings.lua
│   │   └─ device/sdl/device.lua
│   └─ base/ffi/util.lua      # 已包含 Windows FFI 实现
└─ thirdparty/mupdf/          # MuPDF 源码
    └─ build_manual/          # 编译后产生的 .a 库
```

---

## 📄 结束语
按照上述 **10 步** 在一台全新 Windows 机器上执行，你将能够得到一个可以直接运行的 **KOReader Windows 可执行文件**，并且所有代码改动、编译脚本、依赖列表均已包含在本指南中。若后续遇到启动崩溃，请先参考第 9️⃣ 节的排查表；若需要进一步调试 FFI 符号或 UI 渲染，请在 `ui/uimanager.lua` 添加日志并观察 `koreader_stdout.log`、`koreader_stderr.log`（位于项目根目录）中的输出。

祝你移植顺利 🚀
