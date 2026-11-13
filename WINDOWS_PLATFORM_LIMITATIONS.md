# Windows 版本的具体限制和问题

## 🔴 系统级限制（设计决定）

### 1. **没有 fork() 系统调用**

**问题**：Windows 不支持 POSIX fork()

**影响**：
```lua
-- 在 Linux/macOS 上可以这样做：
local pid = ffi.C.fork()
if pid == 0 then
    -- 子进程
    doSomething()
    os.exit(0)
else
    -- 父进程
    waitpid(pid)
end

-- 在 Windows 上：❌ 不工作！
-- Windows 需要用 CreateProcess() 替代
```

**具体受影响的功能**：
- **后台任务** - 不能简单 fork 子进程
- **并发处理** - 需要用线程或其他机制
- **某些插件** - 如果依赖 fork() 会失败

**Windows 替代方案**：
- 使用 `CreateProcess()` 启动新进程
- 使用线程（pthread/Windows threads）
- 使用协程（Lua coroutines）

---

### 2. **没有真正的终端（Terminal）**

**问题**：Windows 下 KOReader 是 GUI 程序，不是控制台程序

**影响**：
```bash
# Linux/macOS:
./koreader  # 在终端中运行，可以看到输出

# Windows:
koreader.exe  # 双击启动，没有控制台窗口
```

**具体受影响的功能**：
- **调试输出** - `print()` 和 `io.write()` 的输出不可见
- **标准输入** - 不能从 stdin 读取
- **交互式调试** - 不能在终端中交互
- **日志** - 只能写到文件，不能实时看

**当前状态**：
- 所有输出重定向到日志文件
- 调试需要查看 `crash.log` 或其他日志文件
- 不能像 Linux 一样在终端中看到实时输出

**如何调试**：
```bash
# 查看日志
tail -f koreader/crash.log

# 或者用 DebugView 等工具捕获 OutputDebugString
```

---

### 3. **没有 /proc 和 /sys 文件系统**

**问题**：Windows 没有这些虚拟文件系统

**影响**：
- 读取进程信息（`/proc/self/...`）
- 读取系统信息（`/sys/class/...`）
- 硬件信息获取

**受影响的功能**：
- 电池状态检测（桌面 PC 通常没有电池）
- CPU 温度读取
- 某些硬件传感器

---

### 4. **信号处理（Signals）不同**

**问题**：Windows 的信号机制与 POSIX 不同

**影响**：
```c
// Linux/macOS:
signal(SIGTERM, handler);
signal(SIGINT, handler);

// Windows:
// 只支持有限的信号：SIGINT, SIGTERM, SIGABRT
// 行为也不完全一样
```

**受影响的功能**：
- 优雅关闭处理
- Ctrl+C 处理
- 进程间通信

---

## 🟡 功能性限制

### 5. **没有 Shell 脚本支持**

**问题**：不能直接运行 `.sh` 脚本

**影响**：
- 构建脚本需要在 MSYS2 中运行
- 某些自动化任务可能不工作
- 插件如果依赖 shell 命令会失败

**解决方案**：
- 使用 PowerShell 或批处理脚本
- 在代码中直接调用 API

---

### 6. **路径分隔符不同**

**问题**：Windows 用 `\`，POSIX 用 `/`

**影响**：
```lua
-- Linux/macOS:
local path = "/home/user/books"

-- Windows:
local path = "C:\\Users\\user\\books"
-- 或
local path = "C:/Users/user/books"  -- 也能工作
```

**当前状态**：应该已经处理好，但可能有边缘情况

---

### 7. **文件系统大小写**

**问题**：Windows 文件系统默认不区分大小写

**影响**：
- `Book.epub` 和 `book.epub` 被视为同一文件
- 某些文件名冲突检测可能不正确

---

## 🟢 已实现的功能

### ✅ 这些功能在 Windows 上**正常工作**：

- **基本阅读** - 打开和阅读电子书
- **格式支持** - EPUB, PDF, MOBI, FB2, DjVu 等
- **UI 交互** - 鼠标、键盘、触摸（如果有）
- **字体渲染** - FreeType 正常工作
- **图像渲染** - 通过 GDI/SDL
- **设置保存** - 配置文件正常保存
- **书签和笔记** - 数据库正常工作
- **字典** - StarDict 字典支持
- **PDF 重排** - koptinterface 工作
- **文件浏览** - 文件系统访问正常

---

## 🔍 需要特别注意的功能

### 可能不工作或有问题的：

1. **SSH 相关功能** - Windows 没有内置 SSH
2. **终端相关插件** - 如果有依赖终端的插件
3. **某些 POSIX 特定的操作** - 符号链接、硬链接
4. **某些网络功能** - 如果依赖 POSIX socket API
5. **设备特定功能** - 电子墨水刷新、前置灯等

---

## 📊 与其他平台的对比

| 功能 | Linux | macOS | Windows | Kindle/Kobo |
|------|-------|-------|---------|-------------|
| fork() | ✅ | ✅ | ❌ | ✅ |
| 终端输出 | ✅ | ✅ | ❌ | ❌ |
| /proc | ✅ | ✅ | ❌ | ✅ |
| Shell 脚本 | ✅ | ✅ | ⚠️ | ⚠️ |
| 信号处理 | ✅ | ✅ | ⚠️ | ✅ |
| 基本阅读 | ✅ | ✅ | ✅ | ✅ |
| 格式支持 | ✅ | ✅ | ✅ | ✅ |
| 触摸屏 | ✅ | ⚠️ | ✅ | ✅ |
| 电子墨水 | ❌ | ❌ | ❌ | ✅ |

---

## 💡 如何检测这些问题

### 运行时检测：

```lua
local Device = require("device")

if Device:isWin32() then
    -- Windows 特定处理
    print("Running on Windows - no fork() available")
    
    -- 使用替代方案
    useThreadsInsteadOfFork()
else
    -- POSIX 系统
    local pid = ffi.C.fork()
    -- ...
end
```

### 编译时检测：

```c
#ifdef _WIN32
    // Windows 特定代码
    CreateProcess(...);
#else
    // POSIX 代码
    fork();
#endif
```

---

## 🎯 总结

### Windows 版本的根本限制：

1. **没有 fork()** - 需要用其他进程/线程机制
2. **没有控制台输出** - 调试需要看日志文件
3. **POSIX API 不完整** - 某些功能需要 Windows API 替代

### 但是：

✅ **核心阅读功能完全正常**
✅ **大部分插件应该能工作**
✅ **用户体验应该是良好的**

### 主要问题不是功能性 bug，而是：
- 🔴 CI 构建不稳定（已缓解）
- 🔴 libs/ 打包问题（待修复）
- 🟡 缺少 Windows 原生集成（文件关联、安装程序等）

---

**一句话总结**：Windows 版本因为平台限制不支持 fork() 和终端输出，但这些不影响核心阅读功能。主要问题是工程问题（CI、打包），不是运行时功能问题。✅
