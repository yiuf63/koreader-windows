#!/bin/bash
# KOReader Windows 本地编译脚本（用于 MSYS2）

export MSYSTEM=MSYS
export PATH=/mingw64/bin:$PATH

cd /d/code/koreader-windows || exit 1

echo "=== 环境检查 ==="
echo "MSYSTEM: $MSYSTEM"
echo "工作目录: $(pwd)"
echo "GCC: $(which x86_64-w64-mingw32-gcc)"
echo "CMake: $(which cmake)"
echo "Ninja: $(which ninja)"
echo ""

echo "=== 开始编译 ==="
make TARGET=win32 -j4

echo ""
echo "=== 编译完成 ==="
if [ -f koreader-win32-x86_64-w64-mingw32/koreader.exe ]; then
    echo "✅ 成功！koreader.exe 已生成"
    ls -lh koreader-win32-x86_64-w64-mingw32/koreader.exe
else
    echo "❌ 失败：未找到 koreader.exe"
    exit 1
fi
