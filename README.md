# 为 Xiaomi Mi Router AX3000T (AN8855) 编译 OpenWrt 主线 + OpenClash

本仓库指导为 **Xiaomi Mi Router AX3000T(AN8855 交换芯片版本)** 从 **OpenWrt 主线 (main)** 编译纯净固件,并集成 **Tailscale**;Clash/Mihomo 客户端 **OpenClash 以独立 apk 提供**(不进固件,避免镜像超原厂 U-Boot 加载上限)。

> **更新要点(相对旧版):**
> - OpenWrt 主线 (内核 ≈6.18) **已原生支持 AN8855 交换芯片**,DTS/驱动都在主线里,不再需要任何 target 源码补丁。
> - ⚠️ **2026-08-14 实测修正:** 主线 stock 目标 `xiaomi_mi-router-ax3000t`(**双分区** ubi_kernel+ubi)在**原厂 U-Boot + AN8855** 上 sysupgrade 后无法持久启动(实测两次落回原厂恢复页)。已在 main 上重建 **单 UBI 目标 `xiaomi_mi-router-ax3000t-an8855`**(与旧 24.10 官方 an8855 布局一致:单 `ubi` 112MB @0x600000),用该目标编译/刷机。
> - 去掉自定义 **fwx 内核补丁** 和 **FanchmWrt 主题**,保持纯净主线。
> - 增加 **OpenClash** 作为额外 feed。
> - 🧰 **内置精简工具集**:iptables+nftables 双栈、zram 内存压缩、核心 netfilter、wireguard 隧道、QoS(tc/cake/fq-pie)、ext4、tcpdump/ipset/tc-full 等诊断工具(内核模块只能编译期打入,已预置;重文件系统/USB 等已剔除以适配原厂 U-Boot 体积上限)。
> - 📡 **软件源(apk)默认换为中科大 USTC 镜像**,国内下载快。
> - 📌 本机分区/UBI/固件状态见 [`ROUTER_STATE.md`](ROUTER_STATE.md)。

---

## 目录

1. [背景说明](#1-背景说明)
2. [环境准备](#2-环境准备)
3. [一键构建](#3-一键构建)
4. [手动步骤(可选)](#4-手动步骤可选)
5. [刷入路由器](#5-刷入路由器)(本机路径见 `ROUTER_STATE.md`)
6. [常见问题](#6-常见问题)

---

## 1. 背景说明

### 硬件配置

| 项目 | 规格 |
|------|------|
| SoC | MediaTek MT7981 (Filogic 820) — 双核 Cortex-A53 |
| 交换芯片 | **Airoha AN8855** (新硬件版本,替代 MT7531) |
| 内存 | 128MB / 256MB / 512MB DDR3 (按批次) |
| 闪存 | 128MB SPI-NAND |
| Wi-Fi | MT7976C 双频 (2.4G + 5G) |
| 网口 | 4x LAN + 1x WAN |

### 主线对 AN8855 的支持方式

主线 `target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-common.dtsi` 同时声明了 **MT7531** 与 **AN8855** 两个交换节点。内核启动时通过 MDIO 探测,只有实际存在的芯片会成功注册为 DSA switch,因此**驱动/网络层面**两份固件通用。⚠️ 但**启动布局必须区分硬件**:
- **AN8855(外挂交换,本机)+ 原厂 U-Boot** → 用 `xiaomi_mi-router-ax3000t-an8855`(**单 UBI**,本仓库重建的目标)。
- MT7531 版 → 官方 `xiaomi_mi-router-ax3000t`(双分区)。
- 刷过 OpenWrt U-Boot → `xiaomi_mi-router-ax3000t-ubootmod`。

> 实测(2026-08-14):AN8855 + 原厂 U-Boot 用 stock 双分区目标 sysupgrade 后无法持久启动,详见 `ROUTER_STATE.md` §0。

---

## 2. 环境准备

### 硬件要求

- Linux x86_64 主机(WSL2 亦可)
- **≥8GB 内存**(推荐 16GB+)
- **≥80GB 空闲硬盘**(首次编译约占 40GB)

### 安装依赖

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-setuptools \
    rsync swig unzip zlib1g-dev file wget ccache

# Arch Linux
sudo pacman -S --needed base-devel gcc git ncurses openssl python3 rsync swig unzip zlib ccache
```

### (国内) 加速下载

主线源码在 git.openwrt.org / GitHub,国内直连可能较慢。OpenWrt 的 git/curl 原生支持 `ALL_PROXY`,不会与 `fakeroot` 冲突:

```bash
export ALL_PROXY=socks5h://你的代理地址:端口
```

---

## 3. 一键构建

```bash
# 1) 准备源码 + feeds + OpenClash + 默认配置
bash setup.sh

# 2) 进入克隆出的目录
cd openwrt-ax3000t

# 3) 微调软件包(确保选中 Target Profile)
make menuconfig

# 4) 编译(建议后台跑,首次约 2–6 小时)
make -j$(nproc) V=s 2>&1 | tee build.log

# 或者一行式:
bash setup.sh build
```

`setup.sh` 会自动:
1. 浅克隆 OpenWrt `main` 分支到 `openwrt-ax3000t/`;
2. 在 `feeds.conf` 追加 OpenClash feed;
3. **应用 `patches/` 里的 an8855 单 UBI 目标补丁**(filogic.mk / platform.sh / 02_network / DTS,已应用则跳过);
4. `./scripts/feeds update -a && install -a`;
5. `make defconfig` 生成默认配置(已含 an8855 目标、Tailscale、**精简工具集**;**不含 OpenClash**,单独编译为 apk);
6. 写入 **USTC apk 镜像**(`CONFIG_VERSIONOPT=y` + `CONFIG_VERSION_REPO`)。

### menuconfig 必查项

| 路径 | 选择 |
|------|------|
| Target System | `MediaTek Ralink ARM` |
| Subtarget | `Filogic 820/830 (MT7981/MT7986)` |
| Target Profile | `Xiaomi Mi Router AX3000T (AN8855)`(单 UBI,新目标;勿选带 `(OpenWrt U-Boot layout)` 的 ubootmod)|
| LuCI → Collections | `luci`(`luci-ssl` 更佳) |
| LuCI → Applications | `luci-app-tailscale-community`、`luci-app-nlbwmon`(**OpenClash 不进固件**,见下方说明) |
| LuCI → Translations | 中文(由 `LUCI_LANG_zh_Hans` 总开关控制,setup.sh 已预置) |
| Global build settings → Image configuration → Release repository | `https://mirrors.ustc.edu.cn/openwrt/snapshots`(USTC 镜像) |

> Tailscale 依赖(`kmod-tun`)会被自动拉入。

> **OpenClash 不再打进固件(单独编译为 apk,`setup.sh` 已改):**
> 其 apk 约 8MB(含 clash core),若直接选入固件会使 initramfs-FIT 超过原厂 U-Boot
> 的加载体积上限(实测 26MB 能启动、34MB 起不来)。现由 `setup.sh build` 在固件编完后
> 单独执行 `make package/feeds/openclash/luci-app-openclash/compile`,产出
> `bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash-*.apk`,装时
> `apk add luci-app-openclash`(会自动拉 `luci-compat`/`luci-lua-runtime`/dnsmasq-full/
> bash/curl/ipset/ruby 等依赖)。

> **内核相关包只能编译期打入(apk 无法安装),`setup.sh` 已预置精简工具集**,包括:
> - zram 内存压缩(`kmod-zram` + `zram-swap`)
> - iptables + nftables 双栈及核心 netfilter kmod(`kmod-ipt-core`/`kmod-nft-*`/`kmod-nf-nathelper` 等)
> - 隧道/虚拟网卡:wireguard / veth / tun / tcp-bbr
> - QoS/tc:`kmod-sched-cake` / `kmod-sched-fq-pie` + `tc-full`
> - 文件系统:ext4
> - 诊断工具:tcpdump / conntrack / ipset / ip-full / ip-bridge / iperf3 / ethtool / mtr / nlbwmon 等
>
> > ⚠️ **为何精简:** 初版一次性加了 179 个 kmod(重文件系统 btrfs/xfs、USB 驱动、
> > 异类隧道/l2tp/team/macsec 等),使 initramfs-FIT 达 27.9MB,超过原厂 U-Boot
> > 加载体积上限(26MB 可启动)导致内核反复 panic/复位。已裁到 26MB 以内。需要更多
> > 功能时 `make menuconfig` 按需勾选,或单独编译为 apk 再装。

> ⚠️ **OpenClash 若需安装,必须带 `luci-compat`:** 主线 LuCI 26 已彻底移除 Lua 运行时,
> 而 OpenClash 是纯 Lua 应用。`apk add luci-app-openclash` 会自动拉入
> `luci-compat`(含 `luci-lua-runtime`);若手动 scp 装 apk 时需一并装上这俩,否则
> `服务 > OpenClash` 菜单**不会出现**。

> ⚠️ **USTC 镜像需同时开启 `VERSIONOPT`:** `VERSION_REPO` 等符号挂在
> `Global build settings → Image configuration` 菜单下,须 `CONFIG_VERSIONOPT=y` 才会写入
> `.config`。`setup.sh` 已自动处理。

---

## 4. 手动步骤(可选)

如不使用 `setup.sh`,可手动:

```bash
# 克隆主线
git clone --depth 1 --branch main --single-branch \
    https://git.openwrt.org/openwrt/openwrt.git openwrt-ax3000t
cd openwrt-ax3000t

# 追加 OpenClash feed
cat >> feeds.conf <<EOF
src-git openclash https://github.com/vernesong/OpenClash.git
EOF

# feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 应用 an8855 单 UBI 目标补丁(关键,见 ROUTER_STATE.md §0)
cp ../patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts target/linux/mediatek/dts/
patch -p1 --forward -i ../patches/0001-add-an8855-target.patch

# 配置 + 编译
make defconfig
make menuconfig   # 务必选 an8855 目标;OpenClash 由 setup.sh 单独编译为 apk
make -j$(nproc) V=s 2>&1 | tee build.log
```

---

## 5. 刷入路由器

> ⚠️ **刷机前必读:** 本机兼容的刷机方式与你的**当前布局**强相关。
> 实机抓取的分区/UBI 卷/固件状态见 [`ROUTER_STATE.md`](ROUTER_STATE.md)(记录于 2026-08-13/14)。
>
> **关键结论(本机,原厂 U-Boot + AN8855):必须用单 UBI 目标
> `xiaomi_mi-router-ax3000t-an8855` 编译;stock 双分区目标 sysupgrade 后无法持久启动。**
> 详见 `ROUTER_STATE.md` §0。

### 编译产物

```bash
ls -lh bin/targets/mediatek/filogic/
```

关键文件(an8855 目标):
- `openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-an8855-initramfs-factory.ubi` — **首次刷入**(从原厂系统/原厂 U-Boot 启动 OpenWrt 内存版)
- `openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-an8855-squashfs-sysupgrade.bin` — **升级**(在线 sysupgrade)

> 体积适中(initramfs-kernel 约 25MB / sysupgrade 约 27MB):内含 LuCI + Tailscale +
> 精简工具集(已裁到原厂 U-Boot 加载上限内)。闪存为单 UBI 112MB,空间充足。
> **OpenClash 已从固件剔除**(单独 apk,避免 initramfs 超原厂 U-Boot 加载上限)。

### 刷入方法

#### A. 本机推荐流程:initramfs 过渡 → sysupgrade

> 适配本机(原厂 U-Boot + AN8855,单 UBI 112MB)。仅适用已运行 OpenWrt 的现状。

**① 刷入 initramfs 内存版(会覆盖当前系统,先备份配置):**

```bash
scp openwrt-*-an8855-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1
mtd -f write /tmp/openwrt-*-an8855-initramfs-factory.ubi ubi
reboot
```

重启进入主线内存系统:LAN IP `192.168.31.1`,WiFi `OpenWrt-AX3000T` / `OpenWrt-AX3000T-5G`(无加密)。

**② 在内存系统里正式 sysupgrade:**

```bash
scp openwrt-*-an8855-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1
sysupgrade -n /tmp/openwrt-*-an8855-squashfs-sysupgrade.bin
```

该 sysupgrade 走单 UBI(`CI_UBIPART="ubi"`),kernel+rootfs+rootfs_data 全部写进同一个 `ubi`
分区,与原厂 U-Boot 兼容,重启即进入持久系统。

**救砖:** 断电 → 按住 Reset → 上电,进入原厂 U-Boot 恢复页 (192.168.31.1) 重刷。

#### B. 后续升级:sysupgrade

```bash
# 上传
scp openwrt-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
# 刷入
ssh root@192.168.31.1 'sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin'
```

或 LuCI → System → Backup / Flash Firmware。

> 首次启动 root 无密码,WiFi 默认开放。请立刻在 LuCI 中设置 root 密码,并在 Wireless 中配置 WiFi 加密。

---

## 6. 常见问题

### Q: 单独编译 OpenClash 时包没出现?

确认 `feeds.conf` 里有 OpenClash feed,并执行过 `./scripts/feeds update -a && ./scripts/feeds install -a`。
OpenClash 不进固件,单独用
`make package/feeds/openclash/luci-app-openclash/compile V=s`
产出 `bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash-*.apk`(setup.sh build 已自动做)。

### Q: 固件里怎么没有 OpenClash?

OpenClash 已从固件剔除(单独 apk),避免 initramfs 超原厂 U-Boot 加载上限。安装方式:

```sh
# 把 setup.sh 单独编译出的 apk 传到路由器,或直接从 apk 源安装
scp bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash-*.apk root@192.168.31.1:/tmp/
ssh root@192.168.31.1 'apk add /tmp/luci-app-openclash-*.apk && apk add luci-compat'
```

会自动拉入 `luci-compat`/`luci-lua-runtime`/dnsmasq-full/bash/curl/ipset/ruby 等依赖。

### Q: 装了 OpenClash 但看不到菜单?

`luci-app-openclash` 已装(在 `usr/share/openclash/`、`/etc/init.d/openclash` 等都有文件),
但**菜单不显示**,原因是:主线 **LuCI 26 移除了 Lua 运行时**,而 OpenClash 是纯 Lua 应用,
必须带 `luci-compat`(含 `luci-lua-runtime`)。

```sh
apk update && apk add luci-compat
/etc/init.d/uhttpd restart
# 刷新 LuCI 页面,服务 > OpenClash 出现后再去 OpenClash 设置里下载核心
```

> 判断法:SSH 进路由器看 `/usr/lib/lua/luci/controller/openclash.lua` 是否存在于**当前系统**。
> 若只有 `usr/share/` 没有 Lua 控制器可加载,即缺 compat。

### Q: 下载极慢/超时?

国内请配置代理:`export ALL_PROXY=socks5h://地址:端口`(git/curl 原生支持,与 fakeroot 不冲突)。

### Q: fakeroot 卡住?

中断后再编译前清理残留守护进程:

```bash
kill -9 $(pgrep -f 'faked|fakeroot') 2>/dev/null
```

### Q: WSL 编译报 `find: relative path in PATH`?

WSL 把 Windows PATH 追加进来导致带空格路径被拆成相对路径。运行时内联清理:

```bash
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':') make package/install V=s
```

详见历史踩坑记录 [`BUILD_EXPERIENCE.md`](BUILD_EXPERIENCE.md)。

### Q: 想换回 24.10 稳定分支?

把 `setup.sh` 里的 `--branch main` 改成 `--branch openwrt-24.10`。24.10 **自带官方
`xiaomi_mi-router-ax3000t-an8855` 单 UBI 目标**(无需自定义,即旧固件所用),同样内置 AN8855 支持。

### Q: 为什么主线 stock 目标刷完 sysupgrade 起不来?

AN8855 + 原厂 U-Boot 只认**单 UBI** 布局。主线 stock 目标是**双分区**(ubi_kernel+ubi),sysupgrade
后重启落回原厂恢复页。已重签方案:在 main 上重建 `-an8855` 单 UBI 目标,用它的 initramfs/sysupgrade
产物刷机。详见 `ROUTER_STATE.md` §0。

---

## 附加参考

- OpenWrt 官方构建文档: https://openwrt.org/docs/guide-developer/build-system/start
- AX3000T 硬件/刷机讨论: https://forum.openwrt.org/t/openwrt-support-for-router-home/180490
- OpenClash: https://github.com/vernesong/OpenClash

---

**许可证:** GPL-2.0,与 OpenWrt 一致。
