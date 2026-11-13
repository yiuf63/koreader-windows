# KOReader Windows 本地编译 - 完整指南

## ❌ 刚才的编译失败原因

缺少必要的编译工具：
- x86_64-w64-mingw32-gcc（MinGW-w64 编译器）
- cmake
- ninja

## ✅ 正确的编译步骤

### 步骤 1：打开正确的终端

**重要**：必须使用 **MSYS2 MSYS** 终端（不是 MINGW64/UCRT64）

1. 打开：`C:\msys64\msys2.exe`
2. 或者在开始菜单搜索：**MSYS2 MSYS**

### 步骤 2：安装编译工具

```bash
# 更新包数据库
pacman -Syu

# 安装必要的工具
pacman -S --needed \
    base-devel \
    mingw-w64-x86_64-toolchain \
    mingw-w64-x86_64-cmake \
    mingw-w64-x86_64-ninja
```

这会安装：
- base-devel（make, autoconf 等）
- mingw-w64-x86_64-gcc（编译器）
- mingw-w64-x86_64-g++（C++ 编译器）
- mingw-w64-x86_64-cmake
- mingw-w64-x86_64-ninja

### 步骤 3：开始编译

```bash
cd /d/code/koreader-windows
make TARGET=win32 -j4
```

参数说明：
- `TARGET=win32` - 指定编译 Windows 版本
- `-j4` - 使用 4 个并行作业（根据你的 CPU 核心数调整）

### 步骤 4：等待编译完成

**预计时间**：
- 首次编译：30-60 分钟（需要编译 30+ 个第三方库）
- 后续编译：5-15 分钟（增量编译）

### 步骤 5：查看结果

编译成功后：
```bash
ls -lh koreader-win32-x86_64-w64-mingw32/koreader.exe
```

输出目录：`koreader-win32-x86_64-w64-mingw32/`

---

## 🔍 为什么之前失败？

### 问题 1：环境不对
```
当前：UCRT64 环境（$MSYSTEM=UCRT64）
需要：MSYS 环境（$MSYSTEM=MSYS）
```

### 问题 2：缺少工具
```
❌ x86_64-w64-mingw32-gcc: command not found
❌ cmake: command not found  
❌ ninja: command not found
```

### 问题 3：pacman 不可用
在 UCRT64 bash 中，pacman 命令路径不正确

---

## 📋 完整的安装和编译命令（复制粘贴）

打开 **MSYS2 MSYS** 终端，然后执行：

```bash
# 1. 更新系统
pacman -Syu

# 2. 安装工具（如果询问，输入 Y 确认）
pacman -S --needed base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja

# 3. 进入项目目录
cd /d/code/koreader-windows

# 4. 开始编译
make TARGET=win32 -j4

# 5. 编译成功后测试
./koreader-win32-x86_64-w64-mingw32/koreader.exe --help
```

---

## 🎯 快速验证环境

在正确的 MSYS 终端中运行：

```bash
echo "MSYSTEM: $MSYSTEM"
which x86_64-w64-mingw32-gcc
which cmake
which ninja
```

**期望输出**：
```
MSYSTEM: MSYS
/mingw64/bin/x86_64-w64-mingw32-gcc
/mingw64/bin/cmake
/mingw64/bin/ninja
```

---

## ⚠️ 常见问题

### Q: 为什么不能在 PowerShell/CMD 中编译？
A: KOReader 的构建系统需要 POSIX 环境（bash, make 等）

### Q: MINGW64 和 MSYS 有什么区别？
A: 
- **MSYS**：提供 POSIX 环境，用于运行构建脚本
- **MINGW64**：提供 Windows 原生工具，不适合运行构建

### Q: 编译需要多少磁盘空间？
A: 大约 3-5 GB（包括源码、构建产物、缓存）

### Q: 可以用 Visual Studio 编译吗？
A: 不行，这个项目使用 MinGW-w64，不兼容 MSVC

---

## 📊 今天的完整工作总结

### 已完成 ✅
1. CI 诊断和修复
2. 上游代码同步（1481 个 commits）
3. 创建 15+ 个文档
4. 分析 Windows 平台限制

### 待完成 ⏳
1. 安装编译工具
2. 本地编译测试
3. 修复 libs/ 打包问题

---

**下一步**：请按照上面的步骤，在 MSYS2 MSYS 终端中安装工具并编译！
