# KOReader Windows 开发环境检查脚本
Write-Host "=== KOReader Windows 开发环境检查 ===" -ForegroundColor Cyan

# 1. Git 配置
Write-Host "`n[1] Git 配置" -ForegroundColor Yellow
$gitUser = git config user.name
$gitEmail = git config user.email
Write-Host "  用户: $gitUser <$gitEmail>"
Write-Host "  分支: $(git branch --show-current)"

# 2. MSYS2 环境
Write-Host "`n[2] MSYS2 环境 (D:\msys64)" -ForegroundColor Yellow
$msys64 = "D:\msys64"
if (Test-Path "$msys64\msys2_shell.cmd") {
    Write-Host "  ✓ MSYS2 已安装" -ForegroundColor Green
    Write-Host "  启动命令: D:\msys64\msys2_shell.cmd -msys"
} else {
    Write-Host "  ✗ MSYS2 未找到" -ForegroundColor Red
}

# 3. 子模块状态
Write-Host "`n[3] 子模块状态" -ForegroundColor Yellow
git submodule status | ForEach-Object {
    if ($_ -match '^\s*([+-]?)([a-f0-9]+)\s+(\S+)') {
        $status = $matches[1]
        $path = $matches[3]
        if ($status -eq '-') {
            Write-Host "  ⊘ $path (未初始化)" -ForegroundColor Red
        } elseif ($status -eq '+') {
            Write-Host "  ≠ $path (版本不匹配)" -ForegroundColor Yellow
        } else {
            Write-Host "  ✓ $path" -ForegroundColor Green
        }
    }
}

# 4. 构建命令提示
Write-Host "`n[4] 构建命令" -ForegroundColor Yellow
Write-Host @"
  在 MSYS2 终端中执行:
    export PATH="/usr/bin:/mingw64/bin:`$PATH"
    make TARGET=win32 -j4
    
  或使用 kodev:
    ./kodev fetch-thirdparty
    ./kodev build
    ./kodev run
"@

Write-Host "`n=== 检查完成 ===" -ForegroundColor Cyan
