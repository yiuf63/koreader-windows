#!/bin/bash
# KOReader Windows 构建脚本
# 在 MSYS2 MinGW 64 终端中运行

set -e

# 设置 PATH — 只在这个脚本内生效，不影响你的终端
export PATH="/mingw64/bin:/usr/bin:$PATH"

# Windows 兼容的临时目录
export TEMP="C:/Users/Yiuf/AppData/Local/Temp"
export TMP="C:/Users/Yiuf/AppData/Local/Temp"
export TMPDIR="C:/Users/Yiuf/AppData/Local/Temp"

# Locale
export LC_ALL=C
export LANG=C

cd /d/Code/koreader/base

# 清理旧构建
rm -rf build/x86_64-w64-mingw32
find . -name "CMakeCache.txt" -delete 2>/dev/null
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null

echo "=== 开始构建 ==="
echo "PATH=$PATH"
echo "TEMP=$TEMP"

make TARGET=win32 -j4 2>&1 | tee /d/Code/koreader/build_log.txt

echo "=== 构建完成 ==="
