# KOReader Windows 版

[English](README_WINDOWS.md) | 中文

这是 [KOReader](https://koreader.rocks) 的**原生 Windows x64 构建**，用 MSYS2 的
MinGW-w64 工具链编译。它是一个普通的 Windows 程序 —— **不需要 Cygwin、不需要
WSL、没有任何 POSIX 模拟层**，目标机器上也不用装任何东西。

## 下载与运行

1. 从 [releases 页面](../../releases) 下载最新的
   `koreader-win32-x86_64-*.zip`。
2. 解压到任意位置（例如 `D:\Apps\`）。压缩包里只有一个 `koreader\` 目录，
   解压到哪就能在哪运行。
3. 运行该目录里的 `koreader.exe`。

想直接打开某本书，把它拖到 `koreader.exe` 上即可，或者：

```
koreader.exe D:\Books\某本书.epub
```

**要求 Windows 10 1903 或更高版本，64 位**。这个 1903 不是保守估计：
构建里在应用清单中声明了 `activeCodePage=UTF-8`，而非 ASCII 路径能正常
工作正是靠它 —— 比如文件名叫 `中文测试书名.epub`，或者安装路径里有带重音的
用户名。1903 之前该清单字段会被忽略，这类名字就会变成乱码。

**没有 32 位版本，而且从名字上看不出来**：`TARGET=win32` 指的是平台，
工具链三元组 `x86_64-w64-mingw32` 里的 `mingw32` 指的是 Win32 API ——
32 位工具链同样用它（`i686-w64-mingw32`）。真正的架构是压缩包名里的
`x86_64`，包内每个 DLL 都是 64 位。`tools/win32/check_arch.sh` 可以
对任意构建报告这一点。

配置、缓存和阅读记录存放在 `%APPDATA%\koreader`，而不是程序目录。设置
`KO_HOME` 环境变量可以改到别处（想把程序和配置都放在 U 盘上时有用）。

### 出问题时怎么办

这个构建是**控制台子系统**程序，所以启动时会有一个终端窗口。双击运行时
该窗口会自动隐藏；从终端启动时则保留 —— 所以只要从 `cmd` 或 PowerShell
启动，就总能看到日志：

```
cd 路径\到\koreader
koreader.exe
```

如果启动不了，看 `%APPDATA%\koreader\crash.log`。

## 已实现的功能

| | |
|---|---|
| **格式** | EPUB、PDF、DjVu、TXT —— 均验证过可打开并渲染 |
| **改变窗口大小后重排** | 支持；内容是重排而非拉伸 |
| **界面** | 48 个内置翻译全部可加载，含中文 |
| **插件** | 可加载并正常工作 |

## 已知限制

- **没有 `fork()`，因此打开文档会阻塞界面。** 其他平台上加载在 fork 出的
  子进程里进行，进度条也是这样实现的。Windows 没有 `fork`，任务只能就地
  执行：打开大文档时界面会卡住，且没有进度条。`CreateProcess` 是显而易见
  的替代方案，但渲染路径不可重入 —— 它会修改 `m_pages`、样式缓存和
  conNode 几何数据，而且绘制路径本身还会通过 `partialRender` 重新渲染 ——
  所以要做对，需要一个无界面入口点和独立的缓存目录（否则全局的
  `cr3cache.inx` 会在进程间共享）。这不是一个可以直接替换的改动。
- **封面提取同样是就地执行**，所以第一次进大目录时会停顿一下用于生成封面，
  之后就走的缓存。
- **没有渲染线程。** crengine 编译时设了 `CR_USE_THREADS 0`，这会让所有
  `LVLock`/`CRENGINE_GUARD` 变成空操作；而渲染又会修改 UI 线程同样要读取的
  文档状态。要启用线程，得先审计那套锁，不是改个开关的事。
- **终端插件** —— 需要 Unix 伪终端（`/dev/ptmx`），ConPTY 是另一套实现。
  该插件会自动禁用。
- **时间同步插件** —— 需要 `ntpd`/`ntpdate` 和 Unix 的特权时钟模型。
  该插件会自动禁用。

## 自行编译

Windows 支持尚未并入上游，所以要克隆这个 fork —— 它的 `base` 子模块已经
指向对应的 `koreader-base` fork：

```sh
git clone --branch win32-port https://github.com/yiuf63/koreader-windows.git
cd koreader-windows
git submodule update --init --recursive
```

然后在 **MSYS** 终端（不是 MINGW64 终端）里：

```sh
export PATH="/usr/bin:/mingw64/bin:$PATH"
make TARGET=win32 -j4
```

用 `-j4` 而不是 `-j$(nproc)`：crengine 有几个编译单元每个峰值接近 1 GB，
同时开八个会把 16 GB 内存耗尽。

前置依赖、运行时目录结构，以及调试时值得了解的 Windows 特有细节，见
[`doc/Building_Windows.md`](doc/Building_Windows.md)。

> **cmake 和 ninja 的两个包都要装，而且必须是 MSYS 版胜出 `PATH` 竞争。**
> 不带前缀的 `cmake`/`ninja` 是 MSYS 版，`mingw-w64-x86_64-` 开头的是原生版。
> 构建会把 MSYS 风格路径写进 `koreader_vars.cmake`，只有 MSYS 版能解析它们 ——
> 用原生版的话 `CMAKE_MODULE_PATH` 会是空的，所有 `include()` 都会报
> "could not find requested file"，而这个报错指向 include 而非 cmake，很有
> 迷惑性。

### 测试

`./kodev test front` 在这个目标上不可用：测试框架依赖 `busted`（来自
luarocks，只为模拟器构建），而且它用 `luajit` 跑测试 —— 而 `luajit` 没有
`koreader.exe` 提供的那些 POSIX 兼容符号。改用：

```sh
tools/win32/run_specs.sh     # 前端测试套件，每个 spec 独立进程
tools/win32/ci_smoke.sh      # 运行时冒烟测试（POSIX shim、DLL、gettext）
tools/win32/check_dlls.sh    # 检查所有 DLL 的依赖是否可解析
```

套件之所以每个 spec 一个进程，是因为有几个 spec 会驱动真实的文档/帧缓冲栈
并把进程搞崩；这样崩一个只损失一个 spec，而不是整轮。当前状态：**76 个 spec
文件、596 条断言、268 条通过、0 崩溃**。剩余的失败没有一个是 Windows 特有的
—— 它们要么需要模拟器测试框架的夹具（屏幕尺寸、`spec/front/unit/data` 下的
文档），要么用到本 runner 未实现的 luassert 功能。

## 架构说明

### 为什么这是一个 `TARGET=win32` 构建，而不是一个 fork

改动都在常规构建系统和平台层里，形态上是可以合并回上游的。没有任何一处是
把共享代码重写成 Windows 专用版本。

### 运行时各部分的对应关系

| 路径 | 内容 |
|------|------|
| `koreader.exe` | 启动器（`base/win_loader.c`） |
| `lua51.dll` | 启动器链接的 LuaJIT 运行时 |
| `libs/` | 共享库，由 `ffi.loadlib` 加载 |
| `common/` | Lua C 扩展模块，由 `require` 加载 |
| `frontend/`、`plugins/`、`reader.lua` 等 | Lua 源码 |

一些值得了解的 Windows 特有细节：

- **DLL 搜索路径。** PE 没有 soname 机制（不同于 ELF 和 Mach-O）：DLL 用
  字面文件名记录依赖，加载器只从可执行文件所在目录和搜索路径里找。因此
  `win_loader.c` 用 `AddDllDirectory` 注册了 `libs/` 和 `common/`。没有这一步，
  `libarchive-13.dll` 找不到就在它旁边的 `libz.dll`。

- **POSIX 符号。** MSVCRT 只导出带下划线前缀的拼写（`_open` 而非 `open`），
  而 Lua 代码调用的是 POSIX 名字。`ffi.C` 是对进程映像及其导入表解析符号的，
  所以 `win32_posix.c` 直接从 `koreader.exe` 导出包装函数，所有调用点无需任何
  Lua 改动即可解析。这些包装函数还会强制二进制模式：CRT 默认以*文本*模式打开
  文件，会把 CRLF 改写掉并悄悄缩短读取 —— 这正是翻译目录（`.mo`，二进制）
  加载失败的原因。

- **DLL 命名。** `libs/` 里多数库有两个名字 —— `ffi/loadlib.lua` 要的规范名
  `lib<name>-<version>.dll`，以及其他 DLL 导入时用的原始拼写。两者是同一个
  文件（硬链接）。见 `base/thirdparty/cmake_modules/install_lib.sh`。

- **符号链接。** 除非另有指定，MSYS2 会把 `ln -s` 退化成*复制*，所以
  `base/Makefile.defs` 设了 `MSYS=winsymlinks:nativestrict`。没有它，构建树会
  悄悄变陈旧：`build/` 下的副本永远不更新 `base/ffi/` 后续的改动。

- **换行符。** Windows 上 `core.autocrlf` 默认开启，所以第三方源码检出时是
  CRLF，而补丁文件存的是 LF。补丁因此用 `--ignore-whitespace` 应用。

- **被打过补丁的子模块会显示为已修改。** crengine 是就地打补丁的子模块，所以
  构建后 `git status` 会显示它被修改。补丁每次都从原始状态重新应用，因此
  `git submodule update --force` 永远是安全的。

## 与上游的关系

这是非官方移植。上游 KOReader 不提供 Windows 构建，本仓库与 KOReader 项目
没有隶属关系。程序本身仍是同一个 KOReader，以 AGPL-3.0 授权 —— 见
[COPYING](COPYING)。

如果你想了解 KOReader 本身，请从
[github.com/koreader/koreader](https://github.com/koreader/koreader) 开始。
