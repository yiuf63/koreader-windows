# MINGW64 失败分析和回退方案

## 失败原因

### 错误信息
```
CMake Error at CMakeLists.txt:8 (include):
  include could not find requested file:
    koreader_external_project
```

### 根本原因
MINGW64 环境下，**CMAKE_MODULE_PATH 没有正确设置**，导致找不到自定义的 CMake 模块：
- 模块位置：`base/thirdparty/cmake_modules/koreader_external_project.cmake`
- 问题：MSYS vs MINGW64 的路径处理差异

### 另一个警告
```
[msystem-mingw64] MINGW64 is deprecated. 
Migrate to UCRT64 or CLANG64.
```

MINGW64 已经被标记为过时。

---

## 问题分析

### MSYS vs MINGW64 的路径差异

#### MSYS 环境
```
/d/code/koreader-windows/base/...
├─ 路径以 POSIX 格式处理
├─ CMake 的 MODULE_PATH 正确设置
└─ 可以找到模块 ✅
```

#### MINGW64 环境
```
D:\code\koreader-windows\base\...
├─ 路径可能混合 Windows/POSIX 格式
├─ CMAKE_MODULE_PATH 设置不正确
└─ 找不到模块 ❌
```

---

## 为什么 wiliwili 可以用 MINGW64？

### 关键差异

| 项目 | 依赖管理 | 构建系统 |
|------|----------|----------|
| wiliwili | 手动管理 | 直接 CMake |
| KOReader | 30+ 子项目 | 复杂的 Make + CMake |

wiliwili 的构建更简单：
```bash
# wiliwili 方式
cmake -B build -S . -G Ninja
cmake --build build
```

KOReader 的构建更复杂：
```bash
# KOReader 方式
make TARGET=win32
├─ base/Makefile
│   ├─ 生成 CMAKE_KOVARS
│   └─ 为 30+ 个库调用 cmake
└─ 复杂的路径处理
```

---

## 决策：回退到 MSYS

### 原因

1. **KOReader 的构建系统设计为 MSYS**
   - 路径处理逻辑针对 MSYS 优化
   - 已在 MSYS 环境中工作多年
   - 切换到 MINGW64 需要大量调整

2. **MINGW64 已被标记为过时**
   - GitHub Actions 建议迁移到 UCRT64/CLANG64
   - 如果要切换，应该直接用 UCRT64

3. **风险/收益比不理想**
   - 需要修改核心构建系统
   - 可能引入更多问题
   - 间歇性 CMake 挂起虽然烦人，但有 timeout 保护

---

## 推荐方案：保持 MSYS + 优化策略

### 方案 A：接受间歇性问题（推荐）✅

**现状**：
- ✅ 代码本身正常
- ✅ Windows 构建可以成功（14 分钟）
- ⚠️ 间歇性 CMake 挂起（40-50% 成功率）
- ✅ Timeout 保护（180 分钟）

**策略**：
```bash
# 多次重试直到成功
gh run rerun <run-id>

# 或使用空提交触发
git commit --allow-empty -m "ci: retrigger"
git push
```

**优点**：
- 不需要修改构建系统
- 风险最低
- 最终会成功

---

### 方案 B：尝试 UCRT64（实验性）🧪

如果真的想改进 CI 稳定性，应该尝试 **UCRT64**（不是 MINGW64）：

```yaml
- uses: msys2/setup-msys2@v2
  with:
    msystem: UCRT64  # ← 现代的 MinGW 环境
    path-type: inherit
    cache: false
```

**优点**：
- 现代化的工具链
- 不像 MINGW64 那样被标记为过时
- 可能没有 pipe 继承问题

**缺点**：
- 仍需要测试路径兼容性
- 可能遇到类似的 MODULE_PATH 问题

---

### 方案 C：本地构建 + 上传（最稳定）🏠

对于正式发布：

```bash
# 在本地 MSYS2 环境中构建
cd /d/code/koreader-windows
make TARGET=win32 -j4

# 生成发布包
make TARGET=win32 update-zip

# 手动上传到 GitHub Releases
gh release upload v1.0.0 koreader-win32.zip
```

**优点**：
- 100% 可控
- 没有 GitHub Actions 的问题
- 构建时间可能更快

**缺点**：
- 不自动化
- 需要本地环境

---

## 立即行动：回退 MINGW64 改动

让我们回退到 MSYS 配置：

```bash
git revert HEAD~2..HEAD
# 或手动修改回 msystem: MSYS
```

---

## 总结

### 今天学到的

1. ✅ **MSYS vs MINGW64 的差异**
   - MSYS: POSIX 环境，适合复杂构建
   - MINGW64: 原生 Windows，适合简单项目

2. ✅ **wiliwili 的成功不能直接复制**
   - 构建系统设计不同
   - 依赖管理方式不同

3. ✅ **路径处理很关键**
   - CMAKE_MODULE_PATH 在不同环境中行为不同
   - KOReader 的构建系统假设 MSYS 环境

### 最终建议

**保持 MSYS 配置** + **接受间歇性问题** + **多次重试策略**

这是当前条件下最实际的方案。

---

**文档生成时间**：2024-11-11 15:10 CST  
**决策**：回退 MINGW64，保持 MSYS  
**原因**：路径兼容性问题，风险/收益比不理想
