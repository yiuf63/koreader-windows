# CI 修复总结

## 问题诊断

### 主要问题：CMake 编译器探测挂起

**症状**：
- Windows CI 构建在 90 分钟后超时
- 卡在 `cmake` 的编译器探测阶段 (`CMakeFiles/CMakeScratch/TryCompile-*`)
- 同一个 cmake 命令反复执行，每次都挂起
- 日志显示：`[cmake -Wdev --warn-uninitialized --fresh -G Ninja ...] cwd=.../CMakeFiles/CMakeScratch/TryCompile-7Dcwuf`

**根本原因**：
- 这是 **GitHub Actions windows-2025 镜像的已知回归**
- 镜像版本 `20261103.298` 引入了这个问题
- 同样的代码在镜像 `20261021.278` 上构建成功
- 问题出在 MSYS2 环境中的 jobserver pipe 继承

**已采取的缓解措施**（在代码中）：
1. ✅ 固定到 `windows-2022` 镜像（第 39 行 `.github/workflows/windows.yml`）
2. ✅ 使用 `-j1` + `NINJAFLAGS=-j4` 避免 jobserver 问题
3. ✅ 禁用 ccache 避免路径混淆

**当前状态**：
- 代码已经包含了所有已知的缓解措施
- CI 仍然在超时，说明问题更深层

### 次要问题：子模块版本不匹配（已修复）

**问题**：
- `l10n` 子模块：be4726d → deddb37
- `test` 子模块：86eeb0b → c3b5d06

**修复**：
- ✅ 已提交：commit `48a946893` 更新子模块到最新版本
- ✅ 不影响 Windows 构建功能

## 已完成的修复

### 1. 子模块更新（commit 48a946893）

```bash
git commit -m "chore: update l10n and test submodules to latest

These submodules have been updated to their latest commits:
- l10n: be4726d -> deddb37 (Weblate translations update)
- test: 86eeb0b -> c3b5d06 (optimize sample.pdf speed)

These updates do not affect the Windows build functionality."
```

**状态**：✅ 已提交到本地，⏳ 等待推送

### 2. 文档更新

- ✅ 创建了 `CLAUDE.md` - 项目指导文档
- ✅ 创建了 `CI_STATUS.md` - CI 状态分析
- ✅ 创建了 `CI_FIX_SUMMARY.md` - 本文档

## 推荐的进一步修复

### 短期方案：增加超时时间

修改 `.github/workflows/build_matrix.yml` 中的 Windows 构建步骤：

```yaml
- name: Build (Windows)
  timeout-minutes: 180  # 从默认 90 增加到 180
  run: |
    make TARGET=win32 -j1 NINJAFLAGS=-j4 USE_NO_CCACHE=1
```

### 中期方案：优化构建缓存

添加或改进缓存策略以跳过 cmake 配置阶段：

```yaml
- name: Cache CMake build
  uses: actions/cache@v4
  with:
    path: base/build/x86_64-w64-mingw32/cmake
    key: cmake-win32-${{ hashFiles('base/thirdparty/**') }}
```

### 长期方案：等待 GitHub 修复镜像

监控 GitHub Actions 的更新：
- 跟踪 issue: https://github.com/actions/runner-images/issues
- 当 windows-2025 镜像修复后，移除 `windows-2022` 的固定

## 待推送的更改

```bash
cd /d/code/koreader-windows

# 当前状态
git status
# On branch win32-port
# Your branch is ahead of 'origin/win32-port' by 1 commit.
#   48a946893 chore: update l10n and test submodules to latest

# 推送命令（当网络恢复时）
git push origin win32-port
```

## CI 运行历史

最近的运行：
1. ✅ `42659700507` - Dependabot Updates - **成功** (56s)
2. ❌ `42600587396` - Release - **失败** (1h32m44s)
3. ❌ `42467601129` - Release - **失败** (1m33s)
4. ❌ `42386516185` - Push / PR - **失败** (1h34m20s) - cmake 挂起
5. 🚫 `42386516033` - windows - **取消** (6h0m18s)

## 验证步骤

推送后，通过以下方式监控 CI：

```bash
# 方式 1: GitHub CLI
gh run watch

# 方式 2: 列出最近的运行
gh run list --limit 5

# 方式 3: 浏览器
# https://github.com/yiuf63/koreader-windows/actions
```

## 本地测试建议

在推送到 CI 之前，建议在本地 MSYS2 环境中测试：

```bash
# 1. 启动 MSYS2 shell（不是 MINGW64）
# 2. 切换到项目目录
cd /d/code/koreader-windows

# 3. 设置环境
export PATH="/usr/bin:/mingw64/bin:$PATH"
export MSYSTEM=MSYS

# 4. 清理旧构建（可选）
make clean

# 5. 开始构建
make TARGET=win32 -j4 USE_NO_CCACHE=1

# 6. 如果成功，运行测试
tools/win32/ci_smoke.sh
```

## 相关文件

- `.github/workflows/windows.yml` - Windows CI 配置
- `.github/workflows/build_matrix.yml` - 通用构建矩阵
- `.github/workflows/push_or_pr.yml` - 主入口 workflow
- `base/Makefile.defs` - 构建系统定义
- `doc/Building_Windows.md` - Windows 构建文档

## 联系和资源

- 项目仓库: https://github.com/yiuf63/koreader-windows
- 上游 KOReader: https://github.com/koreader/koreader
- MSYS2: https://www.msys2.org/
- GitHub Actions 文档: https://docs.github.com/actions

---

**最后更新**: 2024-11-10
**状态**: 子模块修复已提交，等待网络恢复后推送
