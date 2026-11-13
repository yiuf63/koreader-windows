# 上游合并和未完成任务计划

## 📊 当前状态

### CI 重试
- ✅ Release workflow 已重新排队
- 🔄 等待运行完成（预计 20-180 分钟）
- 🎯 成功率：33%，需要重试

### 分支状态
- ✅ 已创建 `sync-upstream-2024-11` 分支
- 📍 当前位置：基于 win32-port 的最新代码
- 🔀 准备合并上游更新

---

## 📋 上游合并情况

### 统计
- **共同祖先**：`e551601fc` (约 10月初)
- **上游新增**：~1481 个 commits
- **win32-port 特有**：~20 个 commits（都是 Windows 相关）

### 最近上游重要更新（11月）
1. ✅ Statistics, VocabBuilder: wal_checkpoint() before syncing (#16383)
2. ✅ Add Croatian keyboard layout (#16386)
3. ✅ koptinterface: render only visible part (#16346)
4. ✅ Kindle: add ColorSoft 2 device IDs (#16380)
5. ✅ TTC/OTC font collections support (#16373)
6. ✅ Button: fix crash on unpainted frame (#16327)
7. ✅ History: minor fixes (#16368)
8. ✅ Fix updating paths when renaming/removing folder (#16360)
9. ✅ Sleep screen image: crop to fit (#16348)
10. ✅ readerfooter: stable pages display (#16340)
... 还有 ~1470 个提交

---

## 🎯 执行计划

### 阶段 1：准备合并（进行中）✅
- [x] 创建新分支 `sync-upstream-2024-11`
- [x] Fetch upstream
- [x] 分析差异
- [ ] 检查可能的冲突

### 阶段 2：合并上游
```bash
# 选项 A：直接 merge（推荐）
git merge upstream/master

# 选项 B：rebase（保持线性历史，但风险较高）
git rebase upstream/master

# 预期冲突区域：
# - .github/workflows/* (CI 配置)
# - base/* (可能有 Windows 特定修改)
# - .ci/* (构建配置)
```

### 阶段 3：解决冲突
**预期冲突文件**：
- `.github/workflows/build_matrix.yml` - Windows timeout 配置
- `.github/workflows/windows.yml` - Windows 特定 workflow
- `.ci/build_jobs.yml` - Windows 构建配置
- `base/Makefile.defs` - Windows 路径相关

**策略**：
- 保留所有 Windows 特定的修改
- 合并上游的改进
- CI 配置以我们的为准（timeout 等）

### 阶段 4：测试
- [ ] 本地测试（如果可能）
- [ ] 推送到 GitHub 触发 CI
- [ ] 检查是否有新问题

---

## 📝 未完成的 Windows 实现

### 从 TODO 和 FIXME 分析需要补充的功能

#### 1. 文件关联和默认程序
```lua
-- frontend/device/windows/device.lua
-- TODO: 注册文件关联（.epub, .pdf, .mobi 等）
-- TODO: 设置为默认阅读器
```

#### 2. Windows 原生功能
```lua
-- TODO: 系统托盘图标
-- TODO: 文件资源管理器右键菜单集成
-- TODO: Windows 通知系统集成
```

#### 3. 性能优化
```c
// base/ffi/framebuffer_mupdf.c
// TODO: Windows GDI 优化
// TODO: Direct2D 支持
```

#### 4. 安装程序
```
-- TODO: 创建 Windows Installer (MSI/NSIS)
-- TODO: 自动更新功能
-- TODO: 卸载程序
```

#### 5. 文档
```
-- TODO: Windows 用户指南
-- TODO: 键盘快捷键文档
-- TODO: 故障排除指南
```

---

## 🔍 检查现有代码中的 TODO

让我搜索一下：
```bash
# 查找 Windows 相关的 TODO
grep -r "TODO.*[Ww]indows" frontend/ base/
grep -r "FIXME.*[Ww]indows" frontend/ base/
grep -r "XXX.*win32" frontend/ base/
```

---

## 💡 优先级建议

### 高优先级（应该做）
1. **合并上游** - 保持同步，获取最新修复和功能
2. **修复 libs/ 路径问题** - 让打包成功
3. **基本文档** - README, 安装指南

### 中优先级（可以做）
4. **文件关联** - 提升用户体验
5. **Windows Installer** - 方便安装
6. **系统托盘** - 后台运行

### 低优先级（可选）
7. **Direct2D 优化** - 性能提升
8. **自动更新** - 维护便利

---

## 🎯 接下来的步骤

### 立即执行（现在）
1. ✅ 等待 CI 重试完成
2. 🔄 开始合并上游（在新分支）
3. 📝 列出 TODO 和 FIXME

### 今天完成
1. 合并上游代码
2. 解决冲突
3. 推送测试

### 本周完成
1. 修复 libs/ 路径问题
2. 完善文档
3. 发布一个稳定的 Windows 版本

---

## 📊 时间估计

| 任务 | 预计时间 | 优先级 |
|------|----------|--------|
| 合并上游 | 2-4 小时 | 高 |
| 解决冲突 | 1-2 小时 | 高 |
| 测试构建 | 1-2 小时 | 高 |
| 修复 libs/ | 1 小时 | 高 |
| 基本文档 | 2 小时 | 高 |
| **总计** | **7-11 小时** | - |

---

## 🚀 开始合并

准备好了吗？我们可以开始合并上游了！

**命令**：
```bash
git merge upstream/master
```

**预期**：会有一些冲突，主要在 CI 配置文件中。

要开始吗？
