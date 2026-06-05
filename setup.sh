#!/bin/bash
# WARNING: This script is part of the build tutorial.
# Do NOT run it directly - refer to README.md for step-by-step instructions.
#
# 一键构建脚本 - 从零开始构建 Xiaomi Mi Router AX3000T (AN8855) 固件
# 用法: source setup.sh
# 然后在目录内按 README.md 教程执行

set -e

OPENWRT_DIR="$(pwd)/openwrt-ax3000t"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/patches"

echo "=== 环境检查 ==="
command -v gcc >/dev/null 2>&1 || { echo "缺少 gcc，请先安装构建依赖"; exit 1; }
echo "  gcc: $(gcc --version | head -1)"

echo ""
echo "=== 步骤 1: 克隆 OpenWrt ==="
if [ ! -d "$OPENWRT_DIR" ]; then
    git clone --depth 1 --branch openwrt-24.10 \
        https://git.openwrt.org/openwrt/openwrt.git "$OPENWRT_DIR"
else
    echo "  目录已存在，跳过克隆"
fi

echo ""
echo "=== 步骤 2: 应用 AN8855 补丁 ==="
cd "$OPENWRT_DIR"

# 复制 DTS 文件
cp "$PATCH_DIR/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts" \
    target/linux/mediatek/dts/

# 应用所有修改
git apply "$PATCH_DIR/openwrt-an8855-changes.patch" 2>/dev/null || \
    echo "  补丁已应用或需手动检查"

echo ""
echo "=== 步骤 3: 更新 feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

echo ""
echo "=== 步骤 4: 配置 ==="
make defconfig
echo "  配置文件已生成"
echo "  运行 'make menuconfig' 可微调软件包选择"

echo ""
echo "=== 步骤 5: 启动编译 ==="
echo "  运行 'make -j\$(nproc) V=s | tee build.log' 开始编译"

echo ""
echo "============================================"
echo "  所有准备已完成！"
echo "  详细步骤请参考 README.md"
echo "============================================"
