# CI 状态分析和修复指南

## 当前问题

### 1. 子模块状态不一致

**问题描述**：
- `l10n` 子模块指向新提交 (deddb37) 而不是期望的 (be4726d)
- `test` 子模块指向新提交 (c3b5d06) 而不是期望的 (86eeb0b)
- 这会导致 CI 中的 `git submodule status` 检查失败

**影响**：
- 不影响实际编译（这些是翻译和测试数据）
- 但会让 git 状态显示为 dirty
- CI 可能会因为子模块不匹配而失败

**修复方法**：

```bash
# 方案 1: 重置子模块到期望版本（需要网络）
cd /d/code/koreader-windows
git submodule update --init --recursive

# 方案 2: 如果网络有问题，手动恢复
cd /d/code/koreader-windows/l10n
git fetch origin
git checkout be4726d0fa58195dbe6f2b868ddafd2b18e472d9

cd /d/code/koreader-windows/test
git fetch origin
git checkout 86eeb0b43d8998d402d203a1ae42d00dbed58037

# 方案 3: 提交子模块更新（如果新版本没问题）
cd /d/code/koreader-windows
git add l10n test
git commit -m "chore: update l10n and test submodules to latest"
```

### 2. SSL 证书问题

**问题描述**：
```
fatal: unable to access 'https://github.com/...': error adding trust anchors from file: C:/Program Files/Git/mingw64/etc/ssl/certs/ca-bundle.crt
```

**原因**：当前在 Cygwin 环境中，Git 的 SSL 证书路径配置不正确

**修复方法**：

```bash
# 临时禁用 SSL 验证（不推荐用于生产）
git config --global http.sslVerify false

# 或者修复证书路径
git config --global http.sslCAInfo /etc/pki/tls/certs/ca-bundle.crt
```

## CI 配置分析

### Windows CI Workflow (.github/workflows/windows.yml)

**关键配置**：
1. ✅ 固定到 `windows-2022` 镜像（避免 2025 镜像的挂起问题）
2. ✅ 使用 `-j1` + `NINJAFLAGS=-j4`（避免 jobserver 问题）
3. ✅ 路径顺序：`/usr/bin:/mingw64/bin:...`（MSYS cmake 必须优先）
4. ✅ 禁用 ccache（避免路径混淆）
5. ✅ 多层测试：check_dlls, check_single_copies, ci_smoke, run_specs

**最近的修复**：
- `525088f` - 不检查 Windows 目标的 FFI cdecls
- `0fef54a` - 使用 `-j1` 和 `NINJAFLAGS=-j4`
- `c47ec8e` - 固定到 windows-2022 镜像

### 其他 Workflows

1. **push_or_pr.yml** - 主入口，触发 lint 和 build
2. **build.yml** - 通用构建 workflow（调用 build_matrix.yml）
3. **lint.yml** - 代码检查（shellcheck, luacheck, 等）

## 如何检查 CI 状态（无需 GitHub CLI 认证）

### 方法 1: 浏览器
访问：https://github.com/yiuf63/koreader-windows/actions

### 方法 2: GitHub API（无认证，有速率限制）
```bash
curl -s "https://api.github.com/repos/yiuf63/koreader-windows/actions/runs?per_page=5" | jq '.workflow_runs[] | {id, name, status, conclusion, created_at}'
```

### 方法 3: 本地模拟 CI 检查

```bash
# 1. Lint 检查
cd /d/code/koreader-windows
./.ci/check.sh

# 2. Windows 构建（需要在 MSYS2 中）
# 启动 MSYS2 shell，然后：
cd /d/code/koreader-windows
export PATH="/usr/bin:/mingw64/bin:$PATH"
export MSYSTEM=MSYS
make TARGET=win32 -j1 NINJAFLAGS=-j4 USE_NO_CCACHE=1

# 3. 运行 Windows 测试
tools/win32/check_dlls.sh
tools/win32/check_single_copies.sh
tools/win32/ci_smoke.sh
tools/win32/run_specs.sh
```

## 推荐的修复步骤

### 立即执行（修复子模块问题）

```bash
cd /d/code/koreader-windows

# 选项 A: 如果你想保留最新的子模块版本
git add l10n test
git commit -m "chore: update l10n and test submodules to latest

These submodules have been updated to their latest commits:
- l10n: be4726d -> deddb37
- test: 86eeb0b -> c3b5d06

This does not affect the Windows build."

# 选项 B: 如果你想恢复到原始版本（需要网络）
git submodule update --init --force

# 检查状态
git status
git submodule status
```

### 然后推送（触发 CI）

```bash
git push origin win32-port
```

### 监控 CI

访问：https://github.com/yiuf63/koreader-windows/actions

## 常见 CI 失败原因

1. **编译器内存溢出** - 已通过 `-j4` 修复
2. **Jobserver 挂起** - 已通过 `-j1 NINJAFLAGS=-j4` 修复
3. **CMake 路径问题** - 已通过 PATH 顺序修复
4. **子模块不匹配** - ⚠️ 当前问题
5. **Lint 失败** - 检查 tabs, unscaled sizes, TODO 格式

## 注意事项

1. **必须在 MSYS2 中构建**，不能在 Cygwin 中
2. **子模块浅克隆**（shallow = true），某些 git 操作可能失败
3. **CI 使用 windows-2022 镜像**，本地测试应尽量匹配
4. **构建需要约 2-3GB 磁盘空间**和 **16GB+ 内存**
