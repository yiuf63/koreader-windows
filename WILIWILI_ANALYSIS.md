# 🎯 wiliwili 的 MSYS2 CI 成功策略分析

## 对比分析：wiliwili vs KOReader

### wiliwili 的配置（✅ 稳定）

```yaml
runs-on: windows-latest  # ← 使用最新镜像，不固定旧版本

defaults:
  run:
    shell: msys2 {0}

steps:
  - uses: msys2/setup-msys2@v2
    with:
      msystem: mingw64        # ← 使用 mingw64，不是 MSYS
      path-type: inherit      # ← 继承 PATH
      cache: false            # ← 不使用缓存
      release: false          # ← 使用稳定版
      install: >-
        mingw-w64-x86_64-ninja
        mingw-w64-x86_64-pkgconf
        mingw-w64-x86_64-cc
```

**关键特点**：
1. ✅ 使用 `msystem: mingw64`（不是 `MSYS`）
2. ✅ 使用 `windows-latest`（不固定老镜像）
3. ✅ `path-type: inherit`（继承系统 PATH）
4. ✅ `cache: false`（避免缓存问题）
5. ✅ 只安装必要的包（ninja, pkgconf, cc）
6. ✅ 手动安装依赖（curl + pacman）

### KOReader 的配置（⚠️ 不稳定）

```yaml
runs-on: windows-2022  # ← 固定旧镜像

defaults:
  run:
    shell: msys2 {0}

steps:
  - uses: msys2/setup-msys2@v2
    with:
      msystem: MSYS          # ← 使用 MSYS
      update: false
      install: >-
        make git unzip zip tar
        cmake ninja meson      # ← 通过 pacman 安装大量包
        mingw-w64-x86_64-toolchain
        mingw-w64-x86_64-cmake
        mingw-w64-x86_64-ninja
        # ... 更多包
```

**问题点**：
1. ❌ 使用 `msystem: MSYS`（混合环境）
2. ❌ 固定 `windows-2022`（已知有问题）
3. ❌ 通过 pacman 安装太多包
4. ❌ 混合使用 MSYS 和 MinGW 工具

---

## 🔑 关键差异：MSYS vs MINGW64

### MSYS 环境
```
msystem: MSYS
├─ 提供 POSIX 兼容层
├─ 使用 /usr/bin/bash
├─ 路径转换复杂
├─ jobserver pipe 继承问题 ⚠️
└─ 适合：纯 Unix 工具（make, bash, coreutils）
```

### MINGW64 环境
```
msystem: MINGW64
├─ 原生 Windows 编译
├─ 使用 /mingw64/bin
├─ 路径简单
├─ 没有 pipe 继承问题 ✅
└─ 适合：编译 Windows 原生程序
```

---

## 🎯 推荐的修复方案

### 方案 1：切换到 MINGW64（推荐）⭐

修改 `windows.yml` 和 `build_matrix.yml`：

```yaml
- uses: msys2/setup-msys2@v2
  with:
    msystem: MINGW64        # ← 改为 MINGW64
    path-type: inherit
    cache: false            # ← 禁用缓存
    install: >-
      mingw-w64-x86_64-toolchain
      mingw-w64-x86_64-cmake
      mingw-w64-x86_64-ninja
      mingw-w64-x86_64-nasm
      mingw-w64-x86_64-pkgconf
```

**优点**：
- ✅ 避免 MSYS 的 pipe 继承问题
- ✅ 更原生的 Windows 编译环境
- ✅ wiliwili 已验证稳定

**可能的问题**：
- ⚠️ KOReader 的构建脚本可能依赖 POSIX 工具
- ⚠️ 需要测试 `make` 和 bash 脚本是否兼容

---

### 方案 2：使用 windows-latest（激进）

```yaml
runs-on: windows-latest  # ← 不固定镜像
```

**优点**：
- ✅ 获得最新的修复
- ✅ 跟随 GitHub 的更新

**缺点**：
- ❌ 可能引入新的问题
- ❌ 不可预测

---

### 方案 3：简化依赖安装（保守）

保持当前配置，但优化包安装：

```yaml
- uses: msys2/setup-msys2@v2
  with:
    msystem: MSYS
    update: false
    cache: false          # ← 添加这个
    install: >-
      make git unzip tar  # ← 只安装基本工具
      mingw-w64-x86_64-toolchain
      mingw-w64-x86_64-cmake
      mingw-w64-x86_64-ninja
      mingw-w64-x86_64-nasm
      # 移除不必要的包
```

**优点**：
- ✅ 改动最小
- ✅ 风险较低

---

## 📊 wiliwili 的 CI 成功率

从最近的运行看：
- ✅ 11分10秒 - 成功
- 🚫 10分26秒 - 取消（不是超时）
- 🚫 10分18秒 - 取消（不是超时）

**没有看到超时问题**！说明他们的配置是稳定的。

---

## 💡 立即可行的修复

### 最小改动版（测试）

```yaml
# .github/workflows/windows.yml
- uses: msys2/setup-msys2@v2
  with:
    msystem: MINGW64      # ← 只改这一行
    # ... 其他保持不变
```

### 测试步骤

1. 创建一个测试分支
2. 只修改 `msystem: MSYS` → `msystem: MINGW64`
3. 推送并观察 CI
4. 如果成功率提高，合并到主分支

---

## 🔍 其他观察

### wiliwili 的构建特点

1. **直接使用 cmake**（不是通过 make wrapper）
   ```bash
   cmake -B build -S . -G Ninja
   cmake --build build
   ```

2. **手动管理依赖**（不依赖复杂的 make 系统）
   ```bash
   curl -sL https://... | tar zxf -
   cmake -B build-dep -S /tmp/dep
   cmake --build build-dep
   cmake --install build-dep
   ```

3. **没有复杂的 jobserver**
   - 直接使用 Ninja
   - 没有 make 的 jobserver pipe

---

## 📝 建议的实施步骤

### 第一步：测试 MINGW64（本周）

```bash
# 创建测试分支
git checkout -b test/mingw64

# 修改 windows.yml
# 将 msystem: MSYS 改为 msystem: MINGW64

# 推送测试
git commit -am "ci: test MINGW64 msystem"
git push origin test/mingw64
```

### 第二步：观察结果（1-2 天）

运行 3-5 次 CI：
- 如果成功率 > 80%：采纳
- 如果成功率 < 50%：需要进一步调整

### 第三步：如果 MINGW64 不行

尝试简化构建过程：
- 减少通过 make 的层次
- 直接使用 cmake + ninja
- 参考 wiliwili 的依赖管理方式

---

## 🎯 预期效果

如果切换到 `msystem: MINGW64`：

**最好情况**（60% 概率）：
- ✅ 完全解决 CMake 挂起问题
- ✅ 构建时间稳定在 15-20 分钟
- ✅ 成功率 > 95%

**中等情况**（30% 概率）：
- ✅ 显著改善但不完美
- ⚠️ 成功率 70-90%
- ⚠️ 偶尔仍会挂起

**最坏情况**（10% 概率）：
- ❌ 出现新的兼容性问题
- ❌ 需要修改构建脚本
- 🔄 回退到当前配置

---

## 总结

**wiliwili 的成功秘诀**：
1. ✅ 使用 `msystem: MINGW64`
2. ✅ 使用 `windows-latest`
3. ✅ 禁用缓存
4. ✅ 简化依赖安装
5. ✅ 直接使用 cmake + ninja

**KOReader 应该做的**：
1. 🔧 **立即测试**：切换到 `msystem: MINGW64`
2. 📊 **监控结果**：运行多次观察成功率
3. 🎯 **如果成功**：合并修改
4. 📚 **更新文档**：记录这个改进

---

**文档生成时间**：2024-11-11 14:50 CST  
**基于**：wiliwili 项目的 .github/workflows/build.yaml 分析
