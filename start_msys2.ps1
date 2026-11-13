# 快速启动 MSYS2 并进入项目目录
Write-Host "启动 MSYS2 开发环境..." -ForegroundColor Cyan
Start-Process "D:\msys64\msys2_shell.cmd" -ArgumentList "-msys", "-defterm", "-here", "-no-start", "-c", "cd /d/code/koreader-windows && export PATH='/usr/bin:/mingw64/bin:`$PATH' && bash"
