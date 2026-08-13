# 为 Xiaomi Mi Router AX3000T (AN8855) 编译 OpenWrt 主线 + OpenClash

本仓库指导为 **Xiaomi Mi Router AX3000T(AN8855 交换芯片版本)** 从 **OpenWrt 主线 (main)** 编译纯净固件,并集成 **OpenClash** (Clash / Mihomo 客户端) 与 **Tailscale**。

> **更新要点(相对旧版):**
> - OpenWrt 主线 (内核 ≈6.18) **已原生支持 AN8855 交换芯片**,DTS/驱动都在主线里,不再需要任何 target 源码补丁。
> - 固件目标与原 AX3000T (MT7531) **共用 stock 布局 `xiaomi_mi-router-ax3000t`**,从原厂 U-Boot 用 `initramfs-factory.ubi` 启动后再 `sysupgrade` 即可。
> - 去掉自定义 **fwx 内核补丁** 和 **FanchmWrt 主题**,保持纯净主线。
> - 增加 **OpenClash** 作为额外 feed。

---

## 目录

1. [背景说明](#1-背景说明)
2. [环境准备](#2-环境准备)
3. [一键构建](#3-一键构建)
4. [手动步骤(可选)](#4-手动步骤可选)
5. [刷入路由器](#5-刷入路由器)
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

主线 `target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-common.dtsi` 同时声明了 **MT7531** 与 **AN8855** 两个交换节点。内核启动时通过 MDIO 探测,只有实际存在的芯片会成功注册为 DSA switch,因此同一份 `xiaomi_mi-router-ax3000t` 固件在两种硬件版本上都能工作。U-Boot 侧也已有"auto switch chip detect"。

> 如果你刷过 OpenWrt 的 U-Boot 想用单 UBI 布局,可改用 `xiaomi_mi-router-ax3000t-ubootmod` 目标(`make menuconfig` 里切换)。

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

# 3) 微调软件包(确保选中 Target Profile 与 luci-app-openclash)
make menuconfig

# 4) 编译(建议后台跑,首次约 2–6 小时)
make -j$(nproc) V=s 2>&1 | tee build.log

# 或者一行式:
bash setup.sh build
```

`setup.sh` 会自动:
1. 浅克隆 OpenWrt `main` 分支到 `openwrt-ax3000t/`;
2. 在 `feeds.conf` 追加 OpenClash feed;
3. `./scripts/feeds update -a && install -a`;
4. `make defconfig` 生成默认配置。

### menuconfig 必查项

| 路径 | 选择 |
|------|------|
| Target System | `MediaTek Ralink ARM` |
| Subtarget | `Filogic 820/830 (MT7981/MT7986)` |
| Target Profile | `Xiaomi Mi Router AX3000T` |
| LuCI → Collections | `luci`(`luci-ssl` 更佳) |
| LuCI → Applications | `luci-app-openclash`、`luci-app-tailscale-community` |
| LuCI → Translations | 中文(由 `LUCI_LANG_zh_Hans` 总开关控制,setup.sh 已预置) |

> OpenClash 依赖(dnsmasq-full / bash / curl / ipset / ruby 等)与 Tailscale 依赖(`kmod-tun`)会被自动拉入。

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

# 配置 + 编译
make defconfig
make menuconfig
make -j$(nproc) V=s 2>&1 | tee build.log
```

---

## 5. 刷入路由器

### 编译产物

```bash
ls -lh bin/targets/mediatek/filogic/
```

关键文件:
- `openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-initramfs-factory.ubi` — **首次刷入**(从原厂系统/原厂 U-Boot 启动 OpenWrt 内存版)
- `openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin` — **升级**(在线 sysupgrade)

### 刷入方法

#### A. 首次:用 XMiR-Patcher / 原厂 U-Boot 引导 initramfs

1. 原厂系统下,用 [XMiR-Patcher](https://github.com/openwrt-xiaomi/xmir-patcher) 把 `initramfs-factory.ubi` 刷到 ubi 分区,或
2. 进原厂 U-Boot 恢复模式(断电按住 Reset → 上电 → LED 闪烁后松开),电脑设静态 IP 后访问恢复页面刷入。
3. 内存版 OpenWrt 启动后,**LAN IP 默认为 `192.168.31.1`**(Xiaomi 习惯,由 setup.sh 注入的 uci-defaults 设置);WiFi 已默认开启(SSID: `OpenWrt-AX3000T` / `OpenWrt-AX3000T-5G`,无加密,方便无网线连接)。浏览器访问 `192.168.31.1` 进入 LuCI。

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

### Q: 编译时 OpenClash 包没有出现?

确认 `feeds.conf` 里有 OpenClash feed,并执行过 `./scripts/feeds update -a && ./scripts/feeds install -a`,然后 `make menuconfig` → LuCI → Applications。

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

把 `setup.sh` 里的 `--branch main` 改成 `--branch openwrt-24.10`。24.10 同样内置了 AN8855 支持(自 2025-01 cherry-pick 起)。

---

## 附加参考

- OpenWrt 官方构建文档: https://openwrt.org/docs/guide-developer/build-system/start
- AX3000T 硬件/刷机讨论: https://forum.openwrt.org/t/openwrt-support-for-xiaomi-ax3000t/180490
- OpenClash: https://github.com/vernesong/OpenClash

---

**许可证:** GPL-2.0,与 OpenWrt 一致。
