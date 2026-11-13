#!/bin/bash
# KOReader Windows 构建脚本

echo "=== KOReader Windows 构建 ==="
echo "项目目录: $(pwd)"
echo ""

# 设置 PATH（MSYS 工具优先）
export PATH="/usr/bin:/mingw64/bin:$PATH"

# 显示工具版本
echo "[工具链版本]"
echo "  GCC: $(gcc --version | head -n1)"
echo "  CMake: $(cmake --version | head -n1)"
echo "  Ninja: $(ninja --version)"
echo ""

# 开始构建
echo "[开始构建]"
echo "  目标: win32"
echo "  并行度: -j4 (避免内存耗尽)"
echo ""

make TARGET=win32 -j4

echo ""
echo "=== 构建完成 ==="
