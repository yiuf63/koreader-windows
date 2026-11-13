#!/bin/bash
# 本地编译 KOReader Windows 版本

echo "=== KOReader Windows 本地编译脚本 ==="
echo ""
echo "当前环境检查："
echo "MSYSTEM: $MSYSTEM"
echo "PATH 前几项: $(echo $PATH | cut -d: -f1-3)"
echo ""

if [ "$MSYSTEM" != "MSYS" ]; then
    echo "❌ 错误：当前在 $MSYSTEM 环境中"
    echo ""
    echo "正确的编译步骤："
    echo "1. 关闭当前终端"
    echo "2. 打开 MSYS2 MSYS 终端（不是 MINGW64）"
    echo "3. 运行以下命令："
    echo ""
    echo "   cd /d/code/koreader-windows"
    echo "   pacman -S --needed base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja"
    echo "   make TARGET=win32"
    echo ""
    echo "或者在当前终端执行："
    echo "   /usr/bin/bash --login"
    echo "   export MSYSTEM=MSYS"
    echo "   cd /d/code/koreader-windows"
    echo "   make TARGET=win32"
    exit 1
fi

echo "✅ 环境正确（MSYS）"
echo ""
echo "开始编译..."
cd /d/code/koreader-windows
make TARGET=win32 -j4
