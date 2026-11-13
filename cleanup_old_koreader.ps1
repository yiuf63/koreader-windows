# KOReader 旧目录清理脚本
# 执行前请确认这些目录确实不再需要

Write-Host "准备清理以下目录:" -ForegroundColor Yellow
Write-Host "  1. D:\code\koreadaer (2874 MB)"
Write-Host "  2. D:\d\code\koreadaer (0.56 MB)"
Write-Host "  3. D:\library\downloads\koreader (607 MB) - 如果是下载的发布包可以保留"
Write-Host ""

$confirm = Read-Host "确认删除前两个目录? (输入 YES 确认)"
if ($confirm -eq "YES") {
    if (Test-Path "D:\code\koreadaer") {
        Remove-Item "D:\code\koreadaer" -Recurse -Force
        Write-Host "✓ 已删除 D:\code\koreadaer" -ForegroundColor Green
    }
    if (Test-Path "D:\d\code\koreadaer") {
        Remove-Item "D:\d\code\koreadaer" -Recurse -Force
        Write-Host "✓ 已删除 D:\d\code\koreadaer" -ForegroundColor Green
    }
    Write-Host "清理完成！" -ForegroundColor Green
} else {
    Write-Host "已取消清理" -ForegroundColor Yellow
}
