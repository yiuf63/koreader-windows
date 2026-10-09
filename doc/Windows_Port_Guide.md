# KOReader 项目分析与 Windows 移植指南

## 一、项目原理

### 1.1 整体架构

KOReader 是一个模块化、可移植的电子书阅读器，架构分为三层：

```
┌─────────────────────────────────────────────────┐
│  前端层 (Lua/LuaJIT)                             │
│  reader.lua → frontend/ui/ → frontend/device/    │
│  plugins/*.koplugin/                             │
├─────────────────────────────────────────────────┤
│  FFI 桥接层 (base/ffi/*.lua)                     │
│  framebuffer / input / SDL / blitbuffer          │
├─────────────────────────────────────────────────┤
│  原生层 (base/*.c, base/thirdparty/)             │
│  LuaJIT + MuPDF + DjVuLibre + Crengine          │
│  + FreeType + HarfBuzz + libjpeg-turbo ...       │
└─────────────────────────────────────────────────┘
```

### 1.2 核心机制

#### 设备抽象层 (`frontend/device/`)

通过检测系统特征文件自动选择设备驱动：

| 特征文件 | 设备 |
|----------|------|
| `/proc/usid` | Kindle |
| `/bin/kobo_config.sh` | Kobo |
| `/ebrmain` | PocketBook |
| `/usr/bin/xochitl` | reMarkable |
| SDL 可用 | 桌面模拟器 |

入口在 `frontend/device.lua:probeDevice()`，返回对应的设备对象。

#### UI 框架 (`frontend/ui/`)

自研 widget 系统，核心是 `UIManager` 单例：
- 管理 widget 栈（窗口层级）
- 事件循环 + 定时任务调度
- 通过 `ffi/framebuffer_*.lua` 直接操作像素
- 不依赖任何外部 UI 库（Qt/GTK/Wx 等）

#### 文档渲染 (`frontend/document/`)

通过 FFI 桥接调用 C 库：

| 格式 | 渲染引擎 |
|------|----------|
| PDF/DjVu | MuPDF (`ffi/mupdf.lua`) |
| EPUB/Mobi/FB2 | Crengine (`credocument.lua` → `cre.cpp`) |
| 扫描 PDF 重排 | k2pdfopt (`koptinterface.lua`) |
| 图片 | libjpeg-turbo, libpng, libwebp |

#### 插件系统 (`frontend/pluginloader.lua`)

目录约定：`plugins/<name>.koplugin/main.lua`
- 自动发现和加载
- 事件处理器包装在沙箱中（错误不影响主程序）
- 37 个内置插件（统计、词典、SSH、终端等）

#### 输入处理 (`frontend/device/input.lua`)

底层用 Linux `evdev` 接口读取触摸/按键事件：
- 硬件设备：直接读 `/dev/input/event*`
- SDL 模拟器：`SDL_PollEvent` → 统一事件格式
- 支持多点触控、手写笔、物理按键

### 1.3 启动流程

```
reader.lua
  → require("setupkoenv")          -- 设置 Lua/FFI 搜索路径
  → userpatch.applyPatches()       -- 用户补丁
  → G_defaults / G_reader_settings -- 加载配置
  → require("device")              -- 设备探测
  → CanvasContext:init(Device)     -- 渲染画布初始化
  → UIManager = require("ui/uimanager")
  → FileManager 或 ReaderUI       -- 启动 UI
  → UIManager:run()                -- 进入事件循环
```

---

## 二、在 Windows 上使用 KOReader

### 2.1 什么是 AppImage

**AppImage** 是 Linux 上的一种「便携式应用打包格式」。它把应用及其所有依赖（库、运行时、配置）打包成一个单独的可执行文件，无需安装，无需 root 权限，不会污染系统。

类似的概念：
- Windows 上的 **Portable 版** / **单文件 EXE**
- macOS 上的 **.app** 包

KOReader 的 GitHub Releases 页面提供了 AppImage 文件，例如：
```
koreader-2024.11-amd64.deb
koreader-2024.11.AppImage        ← 这就是 AppImage
koreader-2024.11.x86_64.AppImage
```

### 2.2 在 Windows 上运行 AppImage 的三种方式

#### 方式一：WSL（推荐，最简单）

```powershell
# 1. 安装 WSL（如果还没装）
wsl --install

# 2. 进入 WSL
wsl

# 3. 下载 AppImage
wget https://github.com/koreader/koreader/releases/download/v2024.11/koreader-2024.11-amd64.AppImage

# 4. 赋予执行权限
chmod +x koreader-*.AppImage

# 5. 运行（需要用 X Server 显示 GUI 窗口）
./koreader-*.AppImage
```

**注意**：WSL 默认没有图形界面。需要配合 X Server 才能看到窗口：
- **VcXsrv**（免费）或 **X410**（Microsoft Store）
- 启动 X Server 后，在 WSL 中设置：`export DISPLAY=:0`

或者用 **WSLg**（Windows 11 自带），直接支持 GUI 应用，无需额外配置。

#### 方式二：提取后用 WSL 运行（纯 Lua 开发用）

```powershell
# 1. 提取 AppImage 内容（不需要 FUSE 支持）
./koreader-*.AppImage --appimage-extract

# 2. 提取出 squashfs-root 目录后，进入 WSL 运行
wsl
cd /mnt/c/path/to/squashfs-root
./AppRun
```

`--appimage-extract` 不需要 Linux FUSE 支持，直接解压出完整文件系统。这对**纯 Lua 前端开发**特别有用——你修改 Lua 文件后直接运行，无需重新编译。

#### 方式三：Docker（隔离环境）

```powershell
# 使用官方 Docker 镜像
docker run -it --rm \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  koreader/koreader
```

### 2.3 推荐的 Windows 开发工作流

```
Windows 宿主机
  ├── VS Code（编辑 Lua 文件）
  │     └── Remote-WSL 插件 → 连接 WSL
  ├── WSL (Ubuntu)
  │     ├── ./kodev build          # 编译模拟器
  │     ├── ./kodev run            # 运行（GUI 窗口显示在 Windows 桌面）
  │     ├── ./kodev test front     # 跑测试
  │     └── ./kodev check          # lint 检查
  └── AppImage（快速查看效果）
```

**步骤**：

1. 安装 WSL + Ubuntu
2. 在 WSL 中克隆仓库并编译：
   ```bash
   sudo apt install git
   git clone https://github.com/koreader/koreader.git
   cd koreader
   ./kodev fetch-thirdparty
   ./kodev build
   ```
3. 用 VS Code 的 Remote-WSL 插辑 Lua 代码
4. 在 WSL 终端运行 `./kodev run` 查看效果
5. Windows 11 下 GUI 窗口直接显示在桌面上

---

## 三、原生 Windows 构建（难度分析）

如果目标是**不依赖 WSL，原生运行 Win32 EXE**，需要面对以下挑战：

### 3.1 构建系统

项目已有 `TARGET=win32` 分支（`Makefile.defs:164`），使用 `x86_64-w64-mingw32` 交叉编译。但实际编译需要：

| 需求 | 说明 |
|------|------|
| MinGW-w64 工具链 | MSYS2 环境下安装 `mingw-w64-x86_64-toolchain` |
| 30+ 个 C 库 | 每个都需要针对 MinGW 编译（MuPDF, DjVuLibre, FreeType, HarfBuzz, libjpeg-turbo, libpng, zlib, SQLite, OpenSSL, curl, libzmq ...） |
| LuaJIT | 需要 Windows 版本，且 FFI 绑定的 POSIX/Linux 头文件不可用 |

### 3.2 Linux 特有 API

| 模块 | 问题 |
|------|------|
| `ffi/linux_input_h.lua` | `linux/input.h` — Windows 无 evdev |
| `ffi/linux_fb_h.lua` | Linux framebuffer — Windows 无此概念 |
| `ffi/posix_h.lua` | POSIX API — Windows 不兼容 |
| `input.lua` | 直接读 `/dev/input/event*` |
| `device.lua` | 检测 `/proc/usid` 等 Linux 路径 |

### 3.3 路径和文件系统

| 问题 | 位置 |
|------|------|
| 路径分隔符 `\` vs `/` | 整个代码库 |
| `.so` vs `.dll` | `setupkoenv.lua:6`, `pluginloader.lua:242` |
| 大小写敏感 | Linux 文件名区分大小写，Windows 不区分 |
| `/proc/` 伪文件系统 | `device.lua` 检测设备 |

### 3.4 Shell 依赖

| 工具 | 问题 |
|------|------|
| `kodev` | bash >= 4.0 脚本，Windows 需要 MSYS2/Git Bash |
| `make` | GNU Make，Windows 需要 MinGW 版本 |
| `luacheck` | Lua 静态分析，需要 LuaRocks 安装 |

### 3.5 工作量预估

| 阶段 | 工作量 | 说明 |
|------|--------|------|
| MSYS2 环境搭建 + 编译第三方库 | 2-4 周 | 最大障碍，30+ 个 C 库逐个适配 |
| FFI 绑定移植 | 1-2 周 | 替换 Linux 头文件为 Win32 API |
| 输入系统移植 | 1 周 | Win32 消息循环替代 evdev |
| 路径和文件系统适配 | 1 周 | 全局搜索替换 + 测试 |
| 集成测试和修复 | 2-4 周 | 各种边界情况 |
| **合计** | **2-4 人月** | |

### 3.6 结论

| 目标 | 推荐方案 |
|------|----------|
| **在 Windows 上阅读电子书** | WSL + AppImage 或直接下载 Android 版 |
| **在 Windows 上开发 Lua 前端** | WSL + VS Code Remote-WSL |
| **原生 Win32 构建** | MSYS2 + 现有 `TARGET=win32` 分支，但工作量大 |
| **仅修改 Lua 代码** | `AppImage --appimage-extract`，修改后直接运行 |

---

## 四、参考资源

- 项目仓库：https://github.com/koreader/koreader
- 构建文档：`doc/Building.md`
- 开发环境 Docker：https://github.com/koreader/virdevenv
- GitHub Releases（下载 AppImage）：https://github.com/koreader/koreader/releases
- WSL 安装：https://learn.microsoft.com/en-us/windows/wsl/install
