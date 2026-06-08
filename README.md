# 从零开始为 Xiaomi Mi Router AX3000T (AN8855) 编译 OpenWrt

本教程面向**同型号 Xiaomi Mi Router AX3000T（替换 AN8855 交换芯片版本）** 的用户，指导从裸机环境开始，完整编译 OpenWrt 固件。

> **注意：** 本固件适用于**外挂 Airoha AN8855 交换芯片**的 AX3000T 硬件版本。原厂 AX3000T 使用 MT7531 交换芯片，请使用主线 OpenWrt 的 `xiaomi_mi-router-ax3000t` 目标。

---

## 目录

1. [背景说明](#1-背景说明)
2. [环境准备](#2-环境准备)
3. [获取 OpenWrt 源码](#3-获取-openwrt-源码)
4. [创建 AN8855 专属设备树](#4-创建-an8855-专属设备树)
5. [添加镜像构建定义](#5-添加镜像构建定义)
6. [添加板级检测脚本](#6-添加板级检测脚本)
7. [配置构建系统](#7-配置构建系统)
8. [编译固件](#8-编译固件)
9. [刷入路由器](#9-刷入路由器)
10. [常见问题](#10-常见问题)

---

## 1. 背景说明

### 硬件配置

| 项目 | 规格 |
|------|------|
| SoC | MediaTek MT7981 (Filogic 820) — 双核 Cortex-A53 |
| 交换芯片 | **Airoha AN8855** (替代原版 MT7531) |
| 内存 | 256MB / 512MB DDR3 |
| 闪存 | 128MB SPI-NAND |
| Wi-Fi | MT7976C 双频 (2.4G + 5G) |
| 网口 | 4x LAN + 1x WAN |

### 闪存分区布局

| 偏移 | 大小 | 分区 | 属性 |
|------|------|------|------|
| 0x000000 | 1MB | BL2 | 只读 |
| 0x100000 | 256KB | Nvram | |
| 0x140000 | 256KB | Bdata | |
| 0x180000 | 2MB | Factory | 只读(含EEPROM) |
| 0x380000 | 2MB | FIP | 只读 |
| 0x580000 | 256KB | crash | 只读 |
| 0x5C0000 | 256KB | crash_log | 只读 |
| **0x600000** | **112MB** | **ubi** | **系统分区** |
| 0x7600000 | 256KB | KF | 只读 |

---

## 2. 环境准备

### 硬件要求

- 一台运行 **Linux x86_64** 的电脑（虚拟机/ WSL 也可）
- **至少 8GB 内存**（推荐 16GB+）
- **至少 80GB 空闲硬盘**（SSD 推荐，首次编译约 40GB）

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

### 验证环境

```bash
gcc --version
python3 --version
git --version
```

---

## 3. 获取 OpenWrt 源码

```bash
# 克隆 OpenWrt 24.10 稳定分支（推荐）
git clone --depth 1 --branch openwrt-24.10 \
    https://git.openwrt.org/openwrt/openwrt.git openwrt-ax3000t
cd openwrt-ax3000t

# 更新并安装 feeds（软件包源）
./scripts/feeds update -a
./scripts/feeds install -a
```

> `--depth 1` 表示浅克隆，只取最新代码，节省空间和时间。

---

## 4. 创建 AN8855 专属设备树

OpenWrt 主线 24.10 的 `mt7981b-xiaomi-mi-router-common.dtsi` **已内置 AN8855 交换芯片**的驱动节点。我们只需要为 AN8855 变体创建新的 DTS 文件。

新建文件 `target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts`：

```dts
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981b-xiaomi-mi-router-ax3000t.dtsi"

/ {
        model = "Xiaomi Mi Router AX3000T (AN8855)";
        compatible = "xiaomi,mi-router-ax3000t-an8855", "mediatek,mt7981";
};

&spi_nand {
        mediatek,nmbm;
        mediatek,bmt-max-ratio = <1>;
        mediatek,bmt-max-reserved-blocks = <64>;
        mediatek,bmt-mtd-overridden-oobsize = <64>;
};

&partitions {
        partition@600000 {
                label = "ubi";
                reg = <0x600000 0x7000000>;
        };
};
```

> **说明：** AN8855 变体使用**单 UBI 分区**（112MB）作为系统分区，而非原厂的"双分区(ubi_kernel+ubi)"布局。

---

## 5. 添加镜像构建定义

编辑 `target/linux/mediatek/image/filogic.mk`，在 `xiaomi_mi-router-ax3000t-ubootmod` 之后添加：

```makefile
define Device/xiaomi_mi-router-ax3000t-an8855
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router AX3000T (AN8855)
  DEVICE_DTS := mt7981b-xiaomi-mi-router-ax3000t-an8855
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_mi-router-ax3000t-an8855
```

> **关键参数说明：**
> - `UBINIZE_OPTS := -E 5`：UBI 预留 5 个物理块给坏块管理
> - `BLOCKSIZE := 128k`：SPI-NAND 擦除块大小
> - `PAGESIZE := 2048`：NAND 页大小
> - `DEVICE_PACKAGES`：WiFi 固件包（MT7915E 芯片 + MT7981 协同固件）

---

## 6. 添加板级检测脚本

OpenWrt 需要识别 AN8855 变体以配置正确的网络、升级方式等。

### 6.1 网络接口配置

编辑 `target/linux/mediatek/filogic/base-files/etc/board.d/02_network`，

在每处 `xiaomi,mi-router-ax3000t|\` 后插入一行 `xiaomi,mi-router-ax3000t-an8855|`。

涉及两处：接口 VLAN 配置和 MAC 地址获取。

### 6.2 Preinit 检测

编辑 `target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface`，同样在对应位置插入 AN8855 条目。

### 6.3 固件升级脚本

编辑 `target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh`，做三处修改：

**a) 初始化 UBI 分区参数**（`xiaomi_initial_setup` 函数内）：

```sh
xiaomi,mi-router-ax3000t-an8855)
    fw_setenv mtdparts "nmbm0:1024k(bl2),256k(Nvram),256k(Bdata),\
        2048k(factory),2048k(fip),256k(crash),256k(crash_log),\
        114688k(ubi),256k(KF)"
    ;;
```

**b) 系统升级入口**（`platform_do_upgrade` 函数）：

AN8855 使用单 UBI 分区，所以使用 `CI_UBIPART` 而非 `CI_KERN_UBIPART`：

```sh
xiaomi,mi-router-ax3000t-an8855)
    CI_UBIPART="ubi"
    nand_do_upgrade "$1"
    ;;
```

---

## 7. 配置构建系统

```bash
# 生成默认配置
make defconfig

# （可选）微调软件包选择
make menuconfig
```

在 menuconfig 中确认：
- **Target System** → `MediaTek Ralink ARM`
- **Subtarget** → `Filogic 820/830 (MT7981/MT7986)`
- **Target Profile** → `Xiaomi Mi Router AX3000T (AN8855)`

### 推荐的额外软件包

| 功能 | 包名 |
|------|------|
| LuCI Web 界面 | `luci-ssl` |
| LuCI 中文语言包 | `luci-i18n-base-zh-cn` |
| 网络唤醒 | `luci-app-wol` |
| 实时流量监控 | `luci-app-statistics` |
| UPnP | `luci-app-upnp` |

---

## 8. 编译固件

### 首次编译（耗时最长，约 2-6 小时）

```bash
# 使用所有 CPU 核心，后台运行
make -j$(nproc) V=s 2>&1 | tee build.log
```

> **注意：** 首次编译需要下载工具链、构建交叉编译器、编译所有选中的包。后续增量编译快得多。
>
> `V=s` 显示详细日志，方便排查错误。

### 启用 ccache 加速后续编译

```bash
make menuconfig
# 在 Global build settings → Use ccache 勾选
```

### 如果编译失败

```bash
# 看最后 50 行错误
tail -50 build.log

# 清理出错的包并重编
make package/<包名>/clean
make -j1 package/<包名>/compile V=s

# 强制重新下载源码包
make package/<包名>/prepare V=s
```

---

## 9. 刷入路由器

### 编译产物位置

```bash
ls -lh bin/targets/mediatek/filogic/
```

你应该能看到：
```
openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-an8855-squashfs-sysupgrade.bin
```

### 刷入方法

#### 方法一：通过 LuCI Web 界面

1. 路由器正常启动 OpenWrt
2. 浏览器访问 `192.168.31.1`
3. 进入 **System → Backup / Flash Firmware**
4. 选择 sysupgrade 固件，上传并刷入

#### 方法二：通过 SSH 命令行

```bash
# 上传固件
scp openwrt-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/

# 登录并刷入
ssh root@192.168.31.1
sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin
```

#### 方法三：通过 U-Boot（不死刷）

1. 路由器断电
2. 按住 **Reset** 键，插电
3. 看到 LED 闪烁后松开
4. 电脑设置静态 IP `192.168.31.10`，浏览器访问 `192.168.31.1`
5. 上传固件刷入

### 首次启动

本固件首次启动时 **WiFi 已默认开启**（无密码），方便在没有网线的情况下连接配置：

| 频段 | SSID | 加密 |
|------|------|------|
| 2.4GHz | `OpenWrt-AX3000T` | 开放（无密码） |
| 5GHz | `OpenWrt-AX3000T-5G` | 开放（无密码） |

> **⚠️ 安全提示：** 首次连接后请尽快通过 LuCI 或 SSH 设置密码：
> - 浏览器访问 `192.168.31.1` 进入 LuCI 管理界面
> - 或在 SSH 中运行 `passwd` 设置 root 密码
> - 在 **Network → Wireless** 中配置 WiFi 加密

---

## 10. 常见问题

### Q: 编译时提示 "No rule to make target" 某些包

运行 `make menuconfig` 看看是不是包被禁用了，或者：

```bash
./scripts/feeds install -a
```

### Q: 编译中途中断了，怎么继续？

直接再跑一次 `make` 即可，OpenWrt 的构建系统支持断点续编。

### Q: 怎么只编译内核？

```bash
make target/linux/compile V=s
```

### Q: 路由器刷入后无法启动？

1. 串口接上（UART TX/RX/GND），观察启动日志
2. 进入 U-Boot 恢复模式，刷回已知好用的固件
3. 检查 DTS 中的分区布局是否与 U-Boot 的 `mtdparts` 一致

### Q: 如何自定义软件包？

```bash
# 重新配置
make menuconfig

# 只编译 firmware（不重编整个 toolchain）
make -j$(nproc) V=s
```

---

## 附加参考

- [OpenWrt 官方文档：Build System](https://openwrt.org/docs/guide-developer/build-system/start)
- [OpenWrt 官方文档：构建说明](https://openwrt.org/docs/guide-developer/toolchain/start)
- [MT7981 Filogic 820 资料](https://www.mediatek.com/products/wi-fi-6-filogic-820)
- [Airoha AN8855 Switch 驱动](https://github.com/ansuelsmth/linux/commits/an8855-v11)

---

**许可证：** 本教程采用 GPL-2.0 许可，与 OpenWrt 保持一致。

**贡献：** 如有问题或改进建议，欢迎提交 Issue 或 PR！
