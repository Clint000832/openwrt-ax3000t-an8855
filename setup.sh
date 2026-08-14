#!/bin/bash
# ============================================================
# 一键构建脚本 - Xiaomi Mi Router AX3000T (AN8855)
#
# 本脚本基于 OpenWrt 主线 (main, ~内核 6.18) 编译。
#
# 重要变化:
#   * 主线 OpenWrt 已原生支持 AN8855 交换芯片 (驱动),但**没有**独立的
#     an8855 启动布局目标,必须手工重建单 UBI 目标
#     (xiaomi_mi-router-ax3000t-an8855)。patches/ 里的补丁会自动打上。
#   * 原厂 U-Boot + AN8855 只能用**单 UBI 布局**才能持久启动;
#     官方 stock 双分区目标 (xiaomi_mi-router-ax3000t) 在本机会落回恢复页,
#     勿用。详见 ROUTER_STATE.md §0。
#   * 无自定义 fwx 内核补丁,保持纯净主线。
#   * 额外集成 OpenClash (luci-app-openclash) 官方 feed。
#   * ⚠️ OpenClash 是 Lua 应用,但主线 LuCI 26 已移除 Lua 运行时,
#     必须同时选中 luci-compat (及其依赖 luci-lua-runtime),否则
#     OpenClash 菜单不会出现。本脚本已自动加 CONFIG_PACKAGE_luci-compat=y。
#
# 用法:
#   1) bash setup.sh          # 只做克隆 + feeds + 配置
#   2) bash setup.sh build    # 直接开始编译
# ============================================================

set -e

export OPENWRT_DIR="$(pwd)/openwrt-ax3000t"
# 外层仓库的 patches/ 目录(含 an8855 目标补丁),相对本脚本所在目录推导
export PATCH_DIR="$(cd "$(dirname "$0")" && pwd)/patches"
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
echo "=== 步骤 2.5: 应用 an8855 单 UBI 目标补丁(关键!) ==="
# 主线 main 只有 stock 双分区 / ubootmod 目标,AN8855 + 原厂 U-Boot 需要
# 独立的单 UBI 目标才能持久启动。补丁文件固化在外层仓库 patches/ 下。
# 若已应用(设备已在 filogic.mk 中定义)则跳过,避免重复打补丁报错。
if grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
    echo "  an8855 目标已存在,跳过打补丁"
else
    echo "  复制 DTS ..."
    cp "${PATCH_DIR}/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts" \
       target/linux/mediatek/dts/
    echo "  应用 filogic.mk / platform.sh / 02_network 补丁 ..."
    patch -p1 --forward -i "${PATCH_DIR}/0001-add-an8855-target.patch"
    echo "  已应用 an8855 目标补丁"
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
         TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855 \
         PACKAGE_luci PACKAGE_luci-ssl LUCI_LANG_zh_Hans \
         PACKAGE_luci-compat PACKAGE_luci-lua-runtime \
         PACKAGE_luci-app-openclash \
         PACKAGE_tailscale PACKAGE_luci-app-tailscale-community; do
    sed -i "/^CONFIG_$s=/d; /^# CONFIG_${s} is not set\$/d" .config
done
cat >> .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_LUCI_LANG_zh_Hans=y

# OpenClash 依赖 Lua,而主线 LuCI 26 已删 Lua,必须带 luci-compat(+lua-runtime)
# 否则 OpenClash 菜单不显示。defconfig 会自动补上其依赖。
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y

CONFIG_PACKAGE_luci-app-openclash=y

CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale-community=y
EOF
make defconfig

echo ""
echo "  已自动选中:"
echo "    Target Profile -> Xiaomi Mi Router AX3000T (AN8855, 单 UBI, 原厂 U-Boot)"
echo "    LuCI (+ SSL,中文) / luci-compat(Lua, OpenClash 必需)"
echo "    OpenClash / Tailscale + luci-app-tailscale-community"
echo ""
echo "  如需调整运行: make menuconfig"

echo ""
echo "=== 步骤 6: 注入首次启动定制(IP 192.168.31.1 / WiFi 自动开启) ==="
UCIDEF_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "$UCIDEF_DIR"
cat > "$UCIDEF_DIR/99-xiaomi-ax3000t-custom" <<'EOF'
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
chmod +x "$UCIDEF_DIR/99-xiaomi-ax3000t-custom"
echo "  已注入: $UCIDEF_DIR/99-xiaomi-ax3000t-custom"
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
