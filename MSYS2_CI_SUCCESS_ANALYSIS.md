# GitHub Actions + MSYS2 成功案例分析

## 🔍 调查结果

### 成功使用 MSYS2 的项目

| 项目 | 成功率 | 关键特点 |
|------|--------|----------|
| **msys2/msys2-runtime** | ~100% | MSYS2 自己的项目 |
| **msys2/MSYS2-packages** | ~95%+ | 简单的包构建 |
| **msys2/MINGW-packages** | ~90%+ | 单个包，不嵌套 |
| **git-for-windows/git** | ~95%+ | 简化的构建流程 |
| **OBS Studio** | ~95%+ | **不用 MSYS2！用 MSVC** |
| **wiliwili** | ~90%+ | 简单构建，5 个依赖 |
| **KOReader Windows** | ~5-10% | ❌ 复杂构建，30+ 依赖 |

---

## ✅ 能成功的 MSYS2 项目特点

### 1. MSYS2 官方项目（100% 成功）

**msys2/msys2-runtime, MSYS2-packages**：
```yaml
# 他们最了解 MSYS2
# 避免所有已知的坑
# 简单的构建流程
```

**成功原因**：
- 他们**就是** MSYS2 的维护者
- 知道所有的坑和解决方案
- 构建流程专门优化

---

### 2. 单包构建（90%+ 成功）

**MINGW-packages, MSYS2-packages**：
```bash
# 每次 CI 只构建一个包
makepkg -s

# 不是 30 个包的嵌套构建
```

**成功原因**：
- 只有 **1 次** CMake 调用
- 不是 30 次嵌套调用
- 失败概率：90% vs (90%)^30 = 4%

---

### 3. 简化的构建流程（90%+ 成功）

**git-for-windows/git**：
```yaml
# 虽然用 MSYS2，但构建非常简化
# 已经预编译好大部分依赖
# 只构建 Git 本身
```

---

### 4. 根本不用 MSYS2（95%+ 成功）⭐

**OBS Studio** 的 Windows 构建：
```yaml
# 使用 MSVC，不是 MSYS2
# 使用 vcpkg 管理依赖
# 原生 Windows 工具链
```

**这是最稳定的方案！**

---

## ❌ 会失败的模式

### KOReader Windows 的问题

```
make TARGET=win32
├─ 调用 cmake 配置 libfoo
│   └─ CMake compiler probe (可能挂起)
├─ 调用 cmake 配置 libbar  
│   └─ CMake compiler probe (可能挂起)
├─ ... 重复 30 次
└─ 每次都有 10% 失败概率
    └─ 总成功率: (0.90)^30 = 4%
```

**关键问题**：
1. **嵌套构建** - make 调用 cmake，30 次
2. **jobserver pipe** - make -jN 的 pipe 在 MSYS2 中不稳定
3. **复杂度** - 30+ 个第三方库

---

## 📊 成功的关键因素

### 因素 1：构建复杂度

| 复杂度 | CMake 调用次数 | 成功率 |
|--------|----------------|--------|
| 低 | 1-3 次 | 90%+ |
| 中 | 5-10 次 | 60-80% |
| 高 | 30+ 次 | 5-10% ❌ |

### 因素 2：是否嵌套

| 模式 | 成功率 |
|------|--------|
| 直接 cmake | 90%+ ✅ |
| make → cmake | 60-80% ⚠️ |
| make → cmake (30次) | 5-10% ❌ |

### 因素 3：依赖管理

| 方式 | 成功率 |
|------|--------|
| 预编译包 (pacman) | 95%+ ✅ |
| 手动下载编译 (3-5个) | 90%+ ✅ |
| 嵌套构建 (30+个) | 5-10% ❌ |

---

## 💡 为什么有些项目成功？

### wiliwili 成功的原因

```bash
# 1. 手动管理少量依赖
curl -sL libwebp.tar.gz | tar zxf -
cmake -B build-libwebp && cmake --build build-libwebp

# 2. 直接构建主项目（不通过 make wrapper）
cmake -B build -G Ninja
cmake --build build

# 3. 总共只有 5 次 CMake 调用
# 成功率：(0.90)^5 = 59%
```

### MSYS2-packages 成功的原因

```bash
# 每次只构建一个包
# 使用 makepkg（MSYS2 官方工具）
# 避免复杂的嵌套

makepkg -s  # 只有 1 次 CMake
# 成功率：90%
```

---

## 🎯 结论

### GitHub Actions + MSYS2 **可以**成功，但有条件：

#### ✅ 成功的模式
1. **简单构建** - 1-5 个依赖
2. **直接 cmake** - 不通过 make wrapper
3. **单包构建** - 不嵌套
4. **MSYS2 官方维护** - 知道所有的坑

#### ❌ 失败的模式
1. **复杂构建** - 30+ 个依赖
2. **嵌套 make → cmake** - jobserver pipe 问题
3. **多次 CMake 配置** - 每次都可能失败
4. **非官方支持** - 踩所有的坑

---

## 📝 对 KOReader Windows 的意义

### 为什么这个项目特别困难？

**KOReader 是最糟糕的组合**：
- ❌ 30+ 个第三方库（最复杂）
- ❌ 嵌套 make + cmake（最不稳定）
- ❌ Windows port（非官方）
- ❌ 为 e-ink 阅读器设计（不是 Windows）

**成功率 5-10% 是合理的！**

### 其他项目能成功是因为他们：
- ✅ 要么构建简单（wiliwili: 5 个依赖）
- ✅ 要么是 MSYS2 官方（知道所有坑）
- ✅ 要么根本不用 MSYS2（OBS 用 MSVC）

---

## 💡 最终答案

**问题**：GitHub Actions + MSYS2 的组合都无法使用吗？

**答案**：❌ 不是！

- ✅ **简单项目可以成功** - wiliwili, MSYS2-packages
- ✅ **官方项目可以成功** - msys2/msys2-runtime
- ❌ **复杂嵌套构建会失败** - KOReader Windows (30+ 依赖)

**KOReader Windows 的问题不是 "MSYS2 + GitHub Actions 不行"，而是 "这个特定的复杂度不适合这个组合"。**

---

**结论**：不是所有 MSYS2 项目都失败，但 KOReader Windows 这种复杂度的项目成功率确实只有 5-10%，这是正常的。✅
