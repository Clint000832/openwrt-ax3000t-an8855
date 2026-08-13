#!/bin/bash
# ============================================================
# 一键构建脚本 - Xiaomi Mi Router AX3000T (AN8855)
#
# 本脚本基于 OpenWrt 主线 (main, ~内核 6.18) 编译。
#
# 重要变化:
#   * 主线 OpenWrt 已原生支持 AN8855 交换芯片 (DTS + 驱动),
#     无需任何 target 源码补丁。
#   * 与原 AX3000T (MT7531) 共用 stock 布局
#     (xiaomi_mi-router-ax3000t),固件通过
#     initramfs-factory.ubi 从原厂 U-Boot 启动刷入。
#   * 无自定义 fwx 内核补丁,保持纯净主线。
#   * 额外集成 OpenClash (luci-app-openclash) 官方 feed。
#
# 用法:
#   1) bash setup.sh          # 只做克隆 + feeds + 配置
#   2) bash setup.sh build    # 直接开始编译
# ============================================================

set -e

export OPENWRT_DIR="$(pwd)/openwrt-ax3000t"
OPENCLASH_URL="https://github.com/vernesong/OpenClash.git"
OPENCLASH_CFG="src-git openclash ${OPENCLASH_URL}"

echo ""
echo "=== 步骤 1: 克隆 OpenWrt 主线 ==="
if [ ! -d "$OPENWRT_DIR" ]; then
    git clone --depth 1 --branch main --single-branch \
        https://git.openwrt.org/openwrt/openwrt.git "$OPENWRT_DIR"
else
    echo "  目录已存在,跳过克隆"
fi

cd "$OPENWRT_DIR"

echo ""
echo "=== 步骤 2: 添加 OpenClash feed ==="
# 注意:必须把 feed 加到官方的 feeds.conf.default(含 luci/packages 等官方源),
# 而不是只新建 feeds.conf(那会让 OpenWrt 只认 feeds.conf 而丢掉官方源)。
if [ ! -f feeds.conf ]; then
    cp feeds.conf.default feeds.conf
fi
if ! grep -q "OpenClash" feeds.conf; then
    cat >> feeds.conf <<EOF
# OpenClash (Clash/Mihomo 客户端)
${OPENCLASH_CFG}
EOF
    echo "  已添加: ${OPENCLASH_CFG}"
else
    echo "  OpenClash feed 已存在,跳过"
fi

echo ""
echo "=== 步骤 3: 更新并安装 feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

echo ""
echo "=== 步骤 4: 生成默认配置 ==="
make defconfig

echo ""
echo "=== 步骤 5: 预置本设备目标 + OpenClash + LuCI ==="
# 用标准 Kconfig 符号种子化 .config,再 defconfig 让它自动补全依赖。
# (符号名遵循 OpenWrt metadata 约定:
#    CONFIG_TARGET_<target>_<subtarget>_DEVICE_<device>)
# 先清掉可能已存在的相关行,避免 "key 多次定义" 警告/被覆盖。
for s in TARGET_mediatek TARGET_mediatek_filogic \
         TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t \
         PACKAGE_luci PACKAGE_luci-ssl LUCI_LANG_zh_Hans \
         PACKAGE_luci-app-openclash \
         PACKAGE_tailscale PACKAGE_luci-app-tailscale-community; do
    sed -i "/^CONFIG_$s=/d; /^# CONFIG_${s} is not set\$/d" .config
done
cat >> .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t=y

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_LUCI_LANG_zh_Hans=y

CONFIG_PACKAGE_luci-app-openclash=y

CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale-community=y
EOF
make defconfig

echo ""
echo "  已自动选中:"
echo "    Target Profile -> Xiaomi Mi Router AX3000T (stock 布局,AN8855 自动支持)"
echo "    LuCI (+ SSL,中文) / OpenClash / Tailscale + luci-app-tailscale-community"
echo ""
echo "  如需调整运行: make menuconfig"

echo ""
echo "=== 步骤 6: 注入首次启动定制(IP 192.168.31.1 / WiFi 自动开启) ==="
UCIDEF_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "$UCIDEF_DIR"
cat > "$UCIDEF_DIR/99-router-home-custom" <<'EOF'
#!/bin/sh
# 首次启动定制:
#   1) LAN 默认 IP 改为 192.168.31.1 (Xiaomi 习惯)
#   2) WiFi 默认开启 (2.4G / 5G,无加密),方便无网线时连接配置

# --- LAN IP ---
uci -q set network.lan.ipaddr='192.168.31.1'
uci -q set network.lan.netmask='255.255.255.0'
uci -q commit network

# --- WiFi 启用 + 开放 SSID ---
# 2.4G 与 5G 的 wifi-device section 通常是 radio0 / radio1
for radio in radio0 radio1; do
    [ -n "$(uci -q get wireless.$radio)" ] || continue
    uci -q set wireless.$radio.disabled='0'

    iface="$(uci -q get wireless.$radio | sed -n 's/.*\(default_radio[0-9]*\).*/\1/p')"
    [ -z "$iface" ] && iface="default_$radio"
    if [ -n "$(uci -q get wireless.$iface)" ]; then
        uci -q set wireless.$iface.disabled='0'
        uci -q set wireless.$iface.encryption='none'
        case "$radio" in
            radio0) uci -q set wireless.$iface.ssid='OpenWrt-AX3000T' ;;
            radio1) uci -q set wireless.$iface.ssid='OpenWrt-AX3000T-5G' ;;
        esac
    fi
done
uci -q commit wireless

# 立即生效
wifi reload 2>/dev/null

exit 0
EOF
chmod +x "$UCIDEF_DIR/99-router-home-custom"
echo "  已注入: $UCIDEF_DIR/99-router-home-custom"
echo "  首次启动: LAN=192.168.31.1, WiFi SSID: OpenWrt-AX3000T / OpenWrt-AX3000T-5G (无加密)"
echo "  请尽快在 LuCI 中设置 root 密码与 WiFi 加密!"

if [ "$1" = "build" ]; then
    echo ""
    echo "=== 步骤 7: 开始编译 ==="
    echo "  运行: make -j\$(nproc) V=s | tee build.log"
    make -j"$(nproc)" V=s 2>&1 | tee build.log
else
    echo ""
    echo "============================================"
    echo "  准备完成!请执行:"
    echo "    make menuconfig   # 可微调软件包(目标已预置)"
    echo "    make -j\$(nproc) V=s | tee build.log"
    echo "============================================"
fi
