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
#   * 内核模块只能编译期打入(无法 apk 安装),因此本脚本预置了完整工具集:
#     iptables 双栈 + 全 netfilter、隧道/vxlan/wireguard、QoS/tc、文件系统、
#     USB 存储/串口/4G 网卡、zram 内存压缩、tcpdump/conntrack/ipset 等诊断工具。
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
# 清空我们即将写入的全部符号,确保脚本可重复执行(多次运行不产生重复 key)。
for s in \
    TARGET_mediatek TARGET_mediatek_filogic \
    TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855 \
    VERSIONOPT VERSION_REPO \
    PACKAGE_luci PACKAGE_luci-ssl LUCI_LANG_zh_Hans \
    PACKAGE_luci-compat PACKAGE_luci-lua-runtime \
    PACKAGE_luci-app-openclash PACKAGE_luci-app-nlbwmon \
    PACKAGE_tailscale PACKAGE_luci-app-tailscale-community \
    PACKAGE_iptables PACKAGE_iptables-nft PACKAGE_ip6tables-nft \
    PACKAGE_xtables-legacy PACKAGE_xtables-nft \
    PACKAGE_iptables-mod-extra PACKAGE_iptables-mod-conntrack-extra \
    PACKAGE_iptables-mod-ipopt PACKAGE_iptables-mod-iprange \
    PACKAGE_iptables-mod-filter PACKAGE_iptables-mod-hashlimit \
    PACKAGE_iptables-mod-nat-extra PACKAGE_iptables-mod-trace \
    PACKAGE_iptables-mod-u32 PACKAGE_iptables-mod-ipset \
    PACKAGE_kmod-ipt-core PACKAGE_kmod-ipt-extra \
    PACKAGE_kmod-ipt-nat PACKAGE_kmod-ipt-nat-extra PACKAGE_kmod-ipt-nat6 \
    PACKAGE_kmod-ipt-conntrack PACKAGE_kmod-ipt-conntrack-extra \
    PACKAGE_kmod-ipt-conntrack-label PACKAGE_kmod-ipt-ipopt \
    PACKAGE_kmod-ipt-iprange PACKAGE_kmod-ipt-filter \
    PACKAGE_kmod-ipt-hashlimit PACKAGE_kmod-ipt-ipset \
    PACKAGE_kmod-ipt-offload PACKAGE_kmod-ipt-raw PACKAGE_kmod-ipt-raw6 \
    PACKAGE_kmod-ipt-u32 PACKAGE_kmod-ipt-physdev \
    PACKAGE_kmod-ipt-rpfilter PACKAGE_kmod-ipt-socket \
    PACKAGE_kmod-ipt-tee PACKAGE_kmod-ipt-tproxy \
    PACKAGE_kmod-ipt-checksum PACKAGE_kmod-ipt-led \
    PACKAGE_kmod-ipt-nflog PACKAGE_kmod-ipt-nfqueue \
    PACKAGE_kmod-ipt-cluster PACKAGE_kmod-ipt-ipsec \
    PACKAGE_kmod-ipt-debug \
    PACKAGE_kmod-nft-bridge PACKAGE_kmod-nft-compat \
    PACKAGE_kmod-nft-connlimit PACKAGE_kmod-nft-queue \
    PACKAGE_kmod-nft-socket PACKAGE_kmod-nft-dup-inet \
    PACKAGE_kmod-nft-netdev PACKAGE_kmod-nft-xfrm PACKAGE_kmod-nft-arp \
    PACKAGE_kmod-nf-nat6 PACKAGE_kmod-nf-ipt PACKAGE_kmod-nf-ipt6 \
    PACKAGE_kmod-nf-ipvs PACKAGE_kmod-nf-ipvs-ftp PACKAGE_kmod-nf-ipvs-sip \
    PACKAGE_kmod-nf-nathelper \
    PACKAGE_kmod-nf-nathelper-amanda PACKAGE_kmod-nf-nathelper-broadcast \
    PACKAGE_kmod-nf-nathelper-extra PACKAGE_kmod-nf-nathelper-h323 \
    PACKAGE_kmod-nf-nathelper-irc PACKAGE_kmod-nf-nathelper-netbios \
    PACKAGE_kmod-nf-nathelper-pptp PACKAGE_kmod-nf-nathelper-sane \
    PACKAGE_kmod-nf-nathelper-sip PACKAGE_kmod-nf-nathelper-snmp \
    PACKAGE_kmod-nf-nathelper-tftp PACKAGE_kmod-nf-conncount \
    PACKAGE_kmod-nf-socket PACKAGE_kmod-nf-dup-inet \
    PACKAGE_kmod-nfnetlink-cthelper PACKAGE_kmod-nfnetlink-cttimeout \
    PACKAGE_kmod-nfnetlink-log PACKAGE_kmod-nfnetlink-queue \
    PACKAGE_kmod-gre PACKAGE_kmod-gre6 PACKAGE_kmod-ipip \
    PACKAGE_kmod-sit PACKAGE_kmod-ip6-tunnel PACKAGE_kmod-ip-vti \
    PACKAGE_kmod-ip6-vti PACKAGE_kmod-iptunnel4 PACKAGE_kmod-iptunnel6 \
    PACKAGE_kmod-vxlan PACKAGE_kmod-geneve PACKAGE_kmod-fou \
    PACKAGE_kmod-fou6 PACKAGE_kmod-udptunnel4 PACKAGE_kmod-udptunnel6 \
    PACKAGE_kmod-wireguard PACKAGE_kmod-veth PACKAGE_kmod-l2tp \
    PACKAGE_kmod-l2tp-eth PACKAGE_kmod-l2tp-ip PACKAGE_kmod-pppol2tp \
    PACKAGE_kmod-ppp-synctty PACKAGE_kmod-bonding PACKAGE_kmod-team \
    PACKAGE_kmod-team-mode-activebackup PACKAGE_kmod-team-mode-broadcast \
    PACKAGE_kmod-team-mode-loadbalance PACKAGE_kmod-team-mode-random \
    PACKAGE_kmod-team-mode-roundrobin PACKAGE_kmod-macsec \
    PACKAGE_kmod-mpls PACKAGE_kmod-vrf PACKAGE_kmod-sctp \
    PACKAGE_kmod-tcp-bbr PACKAGE_kmod-tcp-hybla PACKAGE_kmod-tcp-scalable \
    PACKAGE_kmod-netem PACKAGE_kmod-ipsec PACKAGE_kmod-ipsec4 \
    PACKAGE_kmod-ipsec6 PACKAGE_kmod-xfrm-interface \
    PACKAGE_kmod-sched-core PACKAGE_kmod-sched-cake \
    PACKAGE_kmod-sched-fq-pie PACKAGE_kmod-sched-skbprio \
    PACKAGE_kmod-sched-flower PACKAGE_kmod-sched-bpf \
    PACKAGE_kmod-sched-pie PACKAGE_kmod-sched-red \
    PACKAGE_kmod-sched-prio PACKAGE_kmod-sched-drr \
    PACKAGE_kmod-sched-mqprio PACKAGE_kmod-sched-mqprio-common \
    PACKAGE_kmod-sched-ctinfo PACKAGE_kmod-sched-connmark \
    PACKAGE_kmod-sched-ipset PACKAGE_kmod-sched-act-vlan \
    PACKAGE_kmod-sched-act-police PACKAGE_kmod-sched-act-sample \
    PACKAGE_kmod-fs-ext4 PACKAGE_kmod-fs-f2fs PACKAGE_kmod-fs-exfat \
    PACKAGE_kmod-fs-vfat PACKAGE_kmod-fs-msdos PACKAGE_kmod-fs-ntfs3 \
    PACKAGE_kmod-fs-isofs PACKAGE_kmod-fs-hfsplus PACKAGE_kmod-fs-udf \
    PACKAGE_kmod-fs-configfs PACKAGE_kmod-fs-exportfs \
    PACKAGE_kmod-fs-btrfs PACKAGE_kmod-fs-xfs \
    PACKAGE_kmod-usb-storage PACKAGE_kmod-usb-storage-uas \
    PACKAGE_kmod-usb-storage-extras PACKAGE_kmod-usb-printer \
    PACKAGE_kmod-usb-serial PACKAGE_kmod-usb-serial-ch341 \
    PACKAGE_kmod-usb-serial-ftdi PACKAGE_kmod-usb-serial-cp210x \
    PACKAGE_kmod-usb-serial-pl2303 PACKAGE_kmod-usb-serial-option \
    PACKAGE_kmod-usb-serial-wwan PACKAGE_kmod-usb-net-cdc-eem \
    PACKAGE_kmod-usb-net-cdc-ether PACKAGE_kmod-usb-net-cdc-mbim \
    PACKAGE_kmod-usb-net-cdc-ncm PACKAGE_kmod-usb-net-cdc-subset \
    PACKAGE_kmod-usb-net-huawei-cdc-ncm PACKAGE_kmod-usb-gadget \
    PACKAGE_kmod-usb-gadget-eth PACKAGE_kmod-usb-gadget-serial \
    PACKAGE_kmod-usb-gadget-mass-storage \
    PACKAGE_kmod-nls-cp437 PACKAGE_kmod-nls-cp850 PACKAGE_kmod-nls-cp852 \
    PACKAGE_kmod-nls-cp866 PACKAGE_kmod-nls-cp932 PACKAGE_kmod-nls-cp936 \
    PACKAGE_kmod-nls-cp950 PACKAGE_kmod-nls-iso8859-1 \
    PACKAGE_kmod-nls-iso8859-15 PACKAGE_kmod-nls-utf8 \
    PACKAGE_kmod-nls-ucs2-utils \
    PACKAGE_kmod-softdog PACKAGE_kmod-mtdoops PACKAGE_kmod-fixed-phy \
    PACKAGE_kmod-phylink PACKAGE_kmod-of-mdio PACKAGE_kmod-input-evdev \
    PACKAGE_kmod-input-gpio-keys PACKAGE_kmod-input-gpio-keys-polled \
    PACKAGE_kmod-input-uinput PACKAGE_kmod-leds-pwm PACKAGE_kmod-leds-uleds \
    PACKAGE_kmod-zram PACKAGE_zram-swap \
    PACKAGE_conntrack PACKAGE_conntrackd PACKAGE_ipset \
    PACKAGE_ip-full PACKAGE_tc-full PACKAGE_ip-bridge \
    PACKAGE_tcpdump PACKAGE_iperf3 PACKAGE_ethtool PACKAGE_mtr-json \
    PACKAGE_nlbwmon PACKAGE_curl PACKAGE_wget-ssl PACKAGE_nano \
    PACKAGE_openssl-util PACKAGE_openssh-client PACKAGE_coreutils \
    PACKAGE_htop PACKAGE_iftop; do
    sed -i "/^CONFIG_$s=/d; /^# CONFIG_${s} is not set\$/d" .config
done
cat >> .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y

# 软件源(apk)镜像:换为中科大 USTC,国内下载快
# 注意:VERSION_* 挂在 VERSIONOPT 菜单下,必须先 CONFIG_VERSIONOPT=y 才会生效
CONFIG_VERSIONOPT=y
CONFIG_VERSION_REPO="https://mirrors.ustc.edu.cn/openwrt/snapshots"

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_LUCI_LANG_zh_Hans=y

# OpenClash 依赖 Lua,而主线 LuCI 26 已删 Lua,必须带 luci-compat(+lua-runtime)
# 否则 OpenClash 菜单不显示。defconfig 会自动补上其依赖。
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y

CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale-community=y

# ================= 完整工具集(去"精简"化) =================
# --- zram:内存压缩(zram-swap 依赖 kmod-zram + BusyBox swap 工具) ---
# 注意:BusyBox swap 工具(mkswap/swapon/swapoff)在默认配置下已开启
# (BUSYBOX_DEFAULT_*SWAP*=y),无需 BUSYBOX_CUSTOM,故不额外写入。
CONFIG_PACKAGE_kmod-zram=y
CONFIG_PACKAGE_zram-swap=y

# --- 防火墙:iptables + nftables 双栈 ---
# main 默认 fw4 走 nftables,但保留 iptables 命令族与内核模块,
# 兼容依赖 iptables 的脚本/应用(如 OpenClash 兼容模式、传统教程)。
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_ip6tables-nft=y
CONFIG_PACKAGE_xtables-legacy=y
CONFIG_PACKAGE_xtables-nft=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y
CONFIG_PACKAGE_iptables-mod-ipopt=y
CONFIG_PACKAGE_iptables-mod-iprange=y
CONFIG_PACKAGE_iptables-mod-filter=y
CONFIG_PACKAGE_iptables-mod-hashlimit=y
CONFIG_PACKAGE_iptables-mod-nat-extra=y
CONFIG_PACKAGE_iptables-mod-trace=y
CONFIG_PACKAGE_iptables-mod-u32=y
CONFIG_PACKAGE_iptables-mod-ipset=y

# --- iptables/netfilter 内核模块(全) ---
CONFIG_PACKAGE_kmod-ipt-core=y
CONFIG_PACKAGE_kmod-ipt-extra=y
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-ipt-nat-extra=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_kmod-ipt-conntrack=y
CONFIG_PACKAGE_kmod-ipt-conntrack-extra=y
CONFIG_PACKAGE_kmod-ipt-conntrack-label=y
CONFIG_PACKAGE_kmod-ipt-ipopt=y
CONFIG_PACKAGE_kmod-ipt-iprange=y
CONFIG_PACKAGE_kmod-ipt-filter=y
CONFIG_PACKAGE_kmod-ipt-hashlimit=y
CONFIG_PACKAGE_kmod-ipt-ipset=y
CONFIG_PACKAGE_kmod-ipt-offload=y
CONFIG_PACKAGE_kmod-ipt-raw=y
CONFIG_PACKAGE_kmod-ipt-raw6=y
CONFIG_PACKAGE_kmod-ipt-u32=y
CONFIG_PACKAGE_kmod-ipt-physdev=y
CONFIG_PACKAGE_kmod-ipt-rpfilter=y
CONFIG_PACKAGE_kmod-ipt-socket=y
CONFIG_PACKAGE_kmod-ipt-tee=y
CONFIG_PACKAGE_kmod-ipt-tproxy=y
CONFIG_PACKAGE_kmod-ipt-checksum=y
CONFIG_PACKAGE_kmod-ipt-led=y
CONFIG_PACKAGE_kmod-ipt-nflog=y
CONFIG_PACKAGE_kmod-ipt-nfqueue=y
CONFIG_PACKAGE_kmod-ipt-cluster=y
CONFIG_PACKAGE_kmod-ipt-ipsec=y
CONFIG_PACKAGE_kmod-ipt-debug=y

# --- nftables 扩展内核模块(fw4 下被 ipset/nat/bridge 等引用) ---
CONFIG_PACKAGE_kmod-nft-bridge=y
CONFIG_PACKAGE_kmod-nft-compat=y
CONFIG_PACKAGE_kmod-nft-connlimit=y
CONFIG_PACKAGE_kmod-nft-queue=y
CONFIG_PACKAGE_kmod-nft-socket=y
CONFIG_PACKAGE_kmod-nft-dup-inet=y
CONFIG_PACKAGE_kmod-nft-netdev=y
CONFIG_PACKAGE_kmod-nft-xfrm=y
CONFIG_PACKAGE_kmod-nft-arp=y

# --- nf 核心与 NAT 助手 ---
CONFIG_PACKAGE_kmod-nf-nat6=y
CONFIG_PACKAGE_kmod-nf-ipt=y
CONFIG_PACKAGE_kmod-nf-ipt6=y
CONFIG_PACKAGE_kmod-nf-ipvs=y
CONFIG_PACKAGE_kmod-nf-ipvs-ftp=y
CONFIG_PACKAGE_kmod-nf-ipvs-sip=y
CONFIG_PACKAGE_kmod-nf-nathelper=y
CONFIG_PACKAGE_kmod-nf-nathelper-amanda=y
CONFIG_PACKAGE_kmod-nf-nathelper-broadcast=y
CONFIG_PACKAGE_kmod-nf-nathelper-extra=y
CONFIG_PACKAGE_kmod-nf-nathelper-h323=y
CONFIG_PACKAGE_kmod-nf-nathelper-irc=y
CONFIG_PACKAGE_kmod-nf-nathelper-netbios=y
CONFIG_PACKAGE_kmod-nf-nathelper-pptp=y
CONFIG_PACKAGE_kmod-nf-nathelper-sane=y
CONFIG_PACKAGE_kmod-nf-nathelper-sip=y
CONFIG_PACKAGE_kmod-nf-nathelper-snmp=y
CONFIG_PACKAGE_kmod-nf-nathelper-tftp=y
CONFIG_PACKAGE_kmod-nf-conncount=y
CONFIG_PACKAGE_kmod-nf-socket=y
CONFIG_PACKAGE_kmod-nf-dup-inet=y
CONFIG_PACKAGE_kmod-nfnetlink-cthelper=y
CONFIG_PACKAGE_kmod-nfnetlink-cttimeout=y
CONFIG_PACKAGE_kmod-nfnetlink-log=y
CONFIG_PACKAGE_kmod-nfnetlink-queue=y

# --- 隧道 / 虚拟网卡 / 协议 ---
CONFIG_PACKAGE_kmod-gre=y
CONFIG_PACKAGE_kmod-gre6=y
CONFIG_PACKAGE_kmod-ipip=y
CONFIG_PACKAGE_kmod-sit=y
CONFIG_PACKAGE_kmod-ip6-tunnel=y
CONFIG_PACKAGE_kmod-ip-vti=y
CONFIG_PACKAGE_kmod-ip6-vti=y
CONFIG_PACKAGE_kmod-iptunnel4=y
CONFIG_PACKAGE_kmod-iptunnel6=y
CONFIG_PACKAGE_kmod-vxlan=y
CONFIG_PACKAGE_kmod-geneve=y
CONFIG_PACKAGE_kmod-fou=y
CONFIG_PACKAGE_kmod-fou6=y
CONFIG_PACKAGE_kmod-udptunnel4=y
CONFIG_PACKAGE_kmod-udptunnel6=y
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-l2tp=y
CONFIG_PACKAGE_kmod-l2tp-eth=y
CONFIG_PACKAGE_kmod-l2tp-ip=y
CONFIG_PACKAGE_kmod-pppol2tp=y
CONFIG_PACKAGE_kmod-ppp-synctty=y
CONFIG_PACKAGE_kmod-bonding=y
CONFIG_PACKAGE_kmod-team=y
CONFIG_PACKAGE_kmod-team-mode-activebackup=y
CONFIG_PACKAGE_kmod-team-mode-broadcast=y
CONFIG_PACKAGE_kmod-team-mode-loadbalance=y
CONFIG_PACKAGE_kmod-team-mode-random=y
CONFIG_PACKAGE_kmod-team-mode-roundrobin=y
CONFIG_PACKAGE_kmod-macsec=y
CONFIG_PACKAGE_kmod-mpls=y
CONFIG_PACKAGE_kmod-vrf=y
CONFIG_PACKAGE_kmod-sctp=y
CONFIG_PACKAGE_kmod-tcp-bbr=y
CONFIG_PACKAGE_kmod-tcp-hybla=y
CONFIG_PACKAGE_kmod-tcp-scalable=y
CONFIG_PACKAGE_kmod-netem=y
CONFIG_PACKAGE_kmod-ipsec=y
CONFIG_PACKAGE_kmod-ipsec4=y
CONFIG_PACKAGE_kmod-ipsec6=y
CONFIG_PACKAGE_kmod-xfrm-interface=y

# --- QoS / tc 调度器 ---
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-sched-fq-pie=y
CONFIG_PACKAGE_kmod-sched-skbprio=y
CONFIG_PACKAGE_kmod-sched-flower=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-sched-pie=y
CONFIG_PACKAGE_kmod-sched-red=y
CONFIG_PACKAGE_kmod-sched-prio=y
CONFIG_PACKAGE_kmod-sched-drr=y
CONFIG_PACKAGE_kmod-sched-mqprio=y
CONFIG_PACKAGE_kmod-sched-mqprio-common=y
CONFIG_PACKAGE_kmod-sched-ctinfo=y
CONFIG_PACKAGE_kmod-sched-connmark=y
CONFIG_PACKAGE_kmod-sched-ipset=y
CONFIG_PACKAGE_kmod-sched-act-vlan=y
CONFIG_PACKAGE_kmod-sched-act-police=y
CONFIG_PACKAGE_kmod-sched-act-sample=y

# --- 文件系统(USB 移动盘/存储) ---
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-f2fs=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-msdos=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-fs-isofs=y
CONFIG_PACKAGE_kmod-fs-hfsplus=y
CONFIG_PACKAGE_kmod-fs-udf=y
CONFIG_PACKAGE_kmod-fs-configfs=y
CONFIG_PACKAGE_kmod-fs-exportfs=y
CONFIG_PACKAGE_kmod-fs-btrfs=y
CONFIG_PACKAGE_kmod-fs-xfs=y

# --- USB 存储 / 串口 / 网卡(4G) ---
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb-printer=y
CONFIG_PACKAGE_kmod-usb-serial=y
CONFIG_PACKAGE_kmod-usb-serial-ch341=y
CONFIG_PACKAGE_kmod-usb-serial-ftdi=y
CONFIG_PACKAGE_kmod-usb-serial-cp210x=y
CONFIG_PACKAGE_kmod-usb-serial-pl2303=y
CONFIG_PACKAGE_kmod-usb-serial-option=y
CONFIG_PACKAGE_kmod-usb-serial-wwan=y
CONFIG_PACKAGE_kmod-usb-net-cdc-eem=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-net-cdc-mbim=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ncm=y
CONFIG_PACKAGE_kmod-usb-net-cdc-subset=y
CONFIG_PACKAGE_kmod-usb-net-huawei-cdc-ncm=y
CONFIG_PACKAGE_kmod-usb-gadget=y
CONFIG_PACKAGE_kmod-usb-gadget-eth=y
CONFIG_PACKAGE_kmod-usb-gadget-serial=y
CONFIG_PACKAGE_kmod-usb-gadget-mass-storage=y

# --- 字符集 (FAT/文件系统中文名支持) ---
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-cp850=y
CONFIG_PACKAGE_kmod-nls-cp852=y
CONFIG_PACKAGE_kmod-nls-cp866=y
CONFIG_PACKAGE_kmod-nls-cp932=y
CONFIG_PACKAGE_kmod-nls-cp936=y
CONFIG_PACKAGE_kmod-nls-cp950=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y
CONFIG_PACKAGE_kmod-nls-iso8859-15=y
CONFIG_PACKAGE_kmod-nls-utf8=y
CONFIG_PACKAGE_kmod-nls-ucs2-utils=y

# --- 杂项内核 ---
CONFIG_PACKAGE_kmod-softdog=y
CONFIG_PACKAGE_kmod-mtdoops=y
CONFIG_PACKAGE_kmod-fixed-phy=y
CONFIG_PACKAGE_kmod-phylink=y
CONFIG_PACKAGE_kmod-of-mdio=y
CONFIG_PACKAGE_kmod-input-evdev=y
CONFIG_PACKAGE_kmod-input-gpio-keys=y
CONFIG_PACKAGE_kmod-input-gpio-keys-polled=y
CONFIG_PACKAGE_kmod-input-uinput=y
CONFIG_PACKAGE_kmod-leds-pwm=y
CONFIG_PACKAGE_kmod-leds-uleds=y

# --- 连接跟踪工具 ---
CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_conntrackd=y

# --- IP 集与路由工具 ---
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip-full=y            # 完整 ip 命令(替代 ip-tiny)
CONFIG_PACKAGE_tc-full=y            # 完整 tc 流量控制
CONFIG_PACKAGE_ip-bridge=y

# --- 网络诊断/抓包 ---
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_mtr-json=y          # mtr 仅提供 mtr-json / mtr-nojson 两个 variant
CONFIG_PACKAGE_nlbwmon=y            # 带宽统计守护进程

# --- 基础实用工具 ---
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_openssl-util=y
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_iftop=y
EOF
make defconfig

echo ""
echo "  已自动选中:"
echo "    Target Profile -> Xiaomi Mi Router AX3000T (AN8855, 单 UBI, 原厂 U-Boot)"
echo "    LuCI (+ SSL,中文) / luci-compat(Lua, OpenClash 必需)"
echo "    OpenClash / Tailscale + luci-app-tailscale-community"
echo "    zram 内存压缩 / iptables+nftables 双栈 / 完整 netfilter+隧道+QoS kmod"
echo "    tcpdump / conntrack / ipset / tc-full / 文件系统 / USB 存储 / 诊断工具"
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
