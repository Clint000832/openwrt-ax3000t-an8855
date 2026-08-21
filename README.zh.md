# 为 Xiaomi Mi Router AX3000T (AN8855) 编译 OpenWrt 主线固件

> **日期**：2026-08-21
> **作者**：hugh
> **范围**：基础设施
> **目的**：为搭载 AN8855 交换芯片的 Xiaomi Mi Router AX3000T 编译 OpenWrt 主线固件，集成 Tailscale 与 OpenClash
> **状态**：生效

## 变更记录

| 版本 | 日期 | 作者 | 变更说明 |
|------|------|------|----------|
| 2.0 | 2026-08-21 | hugh | 双语重构：英文规范 README + 中文镜像版，合并 DEVELOPMENT.md，新增架构图 |
| 1.0 | 2026-08-15 | hugh | 初版纯中文文档 |

---

[English](README.md) | [中文](#)

---

> 基于 **OpenWrt 主线 (内核 ≈6.18)** 为 **Xiaomi Mi Router AX3000T (AN8855 交换芯片版)** 编译纯净固件。集成 **Tailscale** 进固件，**OpenClash 以独立 APK 提供**（避免 initramfs 超过原厂 U-Boot 加载上限）。采用**单 UBI 布局**目标 `xiaomi_mi-router-ax3000t-an8855`，兼容原厂 U-Boot 持久启动。

---

## 概览

- **问题**：AX3000T AN8855 版本缺乏官方 OpenWrt 主线目标。主线仅提供双分区目标 `xiaomi_mi-router-ax3000t`，在 AN8855 + 原厂 U-Boot 上 sysupgrade 后无法持久启动（落回恢复页）。
- **原因**：原厂 U-Boot + AN8855 仅支持**单 UBI 分区布局**（kernel+rootfs+rootfs_data 同在一个 `ubi` 分区）。主线双分区布局 (`ubi_kernel` + `ubi`) 导致启动循环。
- **受众**：想在 AX3000T AN8855 上跑主线 OpenWrt 的路由器用户；自建固件的开发者。
- **核心能力**：
  - 单 UBI 目标 `xiaomi_mi-router-ax3000t-an8855` 在主线上通过补丁重建
  - `setup.sh` 一键构建（克隆、打补丁、feeds、配置、编译）
  - Tailscale 内置固件，支持子网通告 (`192.168.31.0/24`)
  - OpenClash 独立 APK，不进固件（避免 initramfs 超限）
  - 精选内核模块集（zram、iptables/nftables 双栈、wireguard、QoS、诊断工具），initramfs <26MB

---

## 功能特性

### 核心
- **单 UBI 固件目标** — 基于 OpenWrt 主线通过 `patches/` 重建；兼容 AN8855 + 原厂 U-Boot 持久启动
- **一键构建** — `bash setup.sh build` 自动完成克隆、补丁、feeds、配置、编译
- **Tailscale 内置** — 预装 `luci-app-tailscale-community`；通告 LAN 子网 (`192.168.31.0/24`)
- **精选内核模块** — zram 交换、iptables+nftables 双栈、wireguard/veth/tun 隧道、QoS (cake/fq-pie)、ext4、tcpdump/ipset/tc-full 诊断工具 — 全部压缩在 26MB initramfs 限制内

### 可选
- **OpenClash 独立 APK** — 单独编译 `make package/feeds/openclash/luci-app-openclash/compile`；安装 `apk add luci-app-openclash`（自动拉取 `luci-compat`）
- **中科大 USTC 软件源** — 默认 `CONFIG_VERSIONOPT=y` + `CONFIG_VERSION_REPO=https://mirrors.ustc.edu.cn/openwrt/snapshots`，国内下载极速

### 实验/进阶
- **OpenWrt 24.10 分支支持** — `bash setup.sh --branch openwrt-24.10 build` 使用官方自带 AN8855 目标（无需补丁）
- **自定义内核/模块选择** — `setup.sh` 后执行 `make menuconfig` 按需勾选

---

## 架构

```mermaid
flowchart TD
    A[开发机] -->|bash setup.sh build| B[OpenWrt 主线源码]
    B --> C[应用 AN8855 补丁\npatches/0001-add-an8855-target.patch\npatches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts]
    C --> D[更新/安装 Feeds\n+ OpenClash feed]
    D --> E[生成 .config\nan8855 目标 + Tailscale +\n精选 kmod 集 + USTC 镜像]
    E --> F[编译固件\nmake -j$(nproc) V=s]
    F --> G[产物\ninitramfs-factory.ubi\nsquashfs-sysupgrade.bin\nOpenClash APK]
    G --> H[路由器\n原厂 U-Boot + AN8855]
    H -->|1. mtd write initramfs| I[Initramfs 内存系统]
    I -->|2. sysupgrade -n| J[持久化 OpenWrt\n单 UBI 布局]
```

**组件**：
- `setup.sh` — 编排克隆、补丁、feeds、配置、可选编译
- `patches/0001-add-an8855-target.patch` — 向 `filogic.mk` 添加 `xiaomi_mi-router-ax3000t-an8855` 设备，`platform.sh` 单 UBI 升级逻辑，`02_network` 网络/MAC 规则
- `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` — 设备树：单 UBI 分区 `partition@600000 { label="ubi"; reg=<0x600000 0x7000000> }`
- `scripts/check-image-size.sh` — 校验 initramfs FIT 内核 ≤26MB（原厂 U-Boot 加载上限）

**数据流**：源码 → 补丁 → Feeds → 配置 → 编译 → 产物 → 路由器 (initramfs → sysupgrade)

**核心入口**：
- `bash setup.sh` — 仅准备源码
- `bash setup.sh build` — 准备 + 完整编译
- `bash setup.sh --branch openwrt-24.10 build` — 基于 24.10 稳定分支编译

---

## 项目结构

```text
openwrt-ax3000t-an8855/
├── patches/
│   ├── 0001-add-an8855-target.patch      # filogic.mk + platform.sh + 02_network
│   ├── mt7981b-xiaomi-mi-router-ax3000t-an8855.dts  # 单 UBI DTS
│   └── VERIFIED_COMMIT                   # 锁定主线已验证 commit SHA
├── scripts/
│   └── check-image-size.sh               # Initramfs 体积校验
├── openwrt-ax3000t/                      # OpenWrt 源码 (gitignored, setup.sh 创建)
├── setup.sh                              # 一键构建编排脚本
├── README.md                             # 英文版 (规范版)
├── README.zh.md                          # 本文件 (中文镜像版)
├── DEVELOPMENT.md                        # 完整开发者指南
├── PROJECT.md                            # 路由器运行时配置 (Tailscale、网络、WiFi)
├── BUILD_EXPERIENCE.md                   # 编译踩坑归档
├── ROUTER_STATE.md                       # 设备分区/UBI/固件状态记录
└── .agent/                               # Agent 工作区状态 (自动生成)
```

---

## 快速开始

### 环境要求

- Linux x86_64 主机 (WSL2 亦可)
- ≥8GB 内存 (推荐 16GB+)
- ≥80GB 空闲磁盘 (首次编译约占 40GB)
- 国内用户需 SOCKS5 代理 (`export ALL_PROXY=socks5h://host:port`)

### 准备

```sh
# 克隆本仓库
git clone <本仓库地址>
cd openwrt-ax3000t-an8855

# (国内) 配置代理加速下载
export ALL_PROXY=socks5h://你的代理:端口

# 仅准备源码 + feeds + 配置 (不编译)
bash setup.sh

# 或：准备并直接编译
bash setup.sh build
```

### 编译

```sh
# 若用 setup.sh (非 build 模式)，进入源码目录
cd openwrt-ax3000t

# 确认目标配置
make menuconfig
# Target System: MediaTek Ralink ARM
# Subtarget: Filogic 820/830 (MT7981/MT7986)
# Target Profile: Xiaomi Mi Router AX3000T (AN8855)

# 编译 (首次 2–6 小时)
make -j$(nproc) V=s 2>&1 | tee build.log
```

### 验证产物

```sh
ls -lh bin/targets/mediatek/filogic/
# 预期产物:
# openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-an8855-initramfs-factory.ubi  (~25MB)
# openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-an8855-squashfs-sysupgrade.bin  (~27MB)
# OpenClash APK: bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash-*.apk
```

---

## 刷入路由器

> ⚠️ **原厂 U-Boot + AN8855 必须用单 UBI 目标。** 切勿使用 stock `xiaomi_mi-router-ax3000t` (双分区)。

### 方式 A：Initramfs 过渡 → Sysupgrade (推荐)

```sh
# 1. 刷入 initramfs (从原厂/恢复页)
scp bin/targets/.../openwrt-*-an8855-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1 'mtd -f write /tmp/openwrt-*-an8855-initramfs-factory.ubi ubi && reboot'

# 2. 在内存系统 (192.168.31.1) 中刷入持久化 sysupgrade
scp bin/targets/.../openwrt-*-an8855-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 'sysupgrade -n /tmp/openwrt-*-an8855-squashfs-sysupgrade.bin'
```

### 方式 B：后续升级

```sh
scp openwrt-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 'sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin'
```

### 刷机后

- LAN: `192.168.31.1`，WiFi: `OpenWrt-AX3000T` / `OpenWrt-AX3000T-5G` (开放)
- **立即在 LuCI 设置 root 密码** 并 **配置 WiFi 加密**
- 安装 OpenClash: `scp <apk> root@192.168.31.1:/tmp/ && ssh root@192.168.31.1 'apk add /tmp/luci-app-openclash-*.apk && apk add luci-compat'`

---

## 开发指南

完整构建环境、定制、排障、贡献指南见 [DEVELOPMENT.md](DEVELOPMENT.md)。

### 常用命令

| 任务 | 命令 |
|------|------|
| 仅准备源码 | `bash setup.sh` |
| 完整编译 | `bash setup.sh build` |
| 24.10 分支编译 | `bash setup.sh --branch openwrt-24.10 build` |
| 菜单配置 | `cd openwrt-ax3000t && make menuconfig` |
| 清理重编 | `cd openwrt-ax3000t && make clean && make -j$(nproc) V=s` |
| 单独编译 OpenClash APK | `cd openwrt-ax3000t && make package/feeds/openclash/luci-app-openclash/compile V=s` |
| 校验镜像体积 | `cd openwrt-ax3000t && ../scripts/check-image-size.sh` |

---

## 配置说明

| 文件 | 用途 |
|------|------|
| `patches/VERIFIED_COMMIT` | 锁定主线 commit，保证可复现构建 |
| `patches/0001-add-an8855-target.patch` | 目标定义 + 升级逻辑 + 网络/MAC 补丁 |
| `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | 设备树 (单 UBI 布局) |
| `setup.sh` | 构建编排、分支选择、commit 锁定 |
| `scripts/check-image-size.sh` | Initramfs FIT 体积校验 (≤26MB) |

### 关键构建选项 (setup.sh 后的 `.config`)

| 选项 | 值 | 用途 |
|------|-----|------|
| `CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855` | `y` | 单 UBI AN8855 目标 |
| `CONFIG_PACKAGE_luci-app-tailscale-community` | `y` | Tailscale LuCI 应用 |
| `CONFIG_PACKAGE_luci-compat` | `y` | OpenClash 所需 Lua 运行时 |
| `CONFIG_VERSIONOPT` | `y` | 启用版本仓库覆盖 |
| `CONFIG_VERSION_REPO` | `https://mirrors.ustc.edu.cn/openwrt/snapshots` | 中科大镜像源 |

---

## 约束与限制

- **仅限原厂 U-Boot** — 需单 UBI 目标；stock 双分区目标会启动循环
- **Initramfs ≤26MB** — 原厂 U-Boot FIT 加载器硬性限制；精选 kmod 集强制执行
- **OpenClash 不进固件** — 仅 APK 形式；需 `luci-compat` (固件已内置)
- **仅适配 AN8855 硬件** — MT7531 版本使用不同目标 (`xiaomi_mi-router-ax3000t`)
- **无 USB/存储 kmod** — 为适配体积预算已排除；如需请单独编译

---

## 常见问题

| 问题 | 解决方案 |
|------|----------|
| `fakeroot` 死锁 | 重新编译前 `kill -9 $(pgrep -f 'faked\|fakeroot')` |
| 下载极慢 | `export ALL_PROXY=socks5h://host:port` (git/curl 原生支持) |
| `find: relative path in PATH` (WSL) | `PATH=$(echo "$PATH" \| tr ':' '\n' \| grep -v '^/mnt/' \| tr '\n' ':') make ...` |
| OpenClash 菜单不显示 | `apk add luci-compat && /etc/init.d/uhttpd restart` |
| Initramfs 体积校验失败 | `menuconfig` 裁减 kmod；检查 `scripts/check-image-size.sh` |
| Sysupgrade 后落回恢复页 | 目标错误 — 必须用 `-an8855` 单 UBI，而非 stock 双分区 |
| 内核补丁报 "No file to patch" | `setup.sh` 用 `REPO_PATCH_DIR` 避免与 OpenWrt `PATCH_DIR` 冲突 |

---

## 贡献

1. Fork & 分支
2. 测试构建：`bash setup.sh build`
3. 校验体积：`scripts/check-image-size.sh`
4. 更新用户可见文档
5. 以 Conventional Commits 格式提交 PR

---

## 许可证

GPL-2.0 — 与 OpenWrt 一致。

---

## 相关链接

- [DEVELOPMENT.md](DEVELOPMENT.md) — 完整构建指南、排障、架构
- [PROJECT.md](PROJECT.md) — 路由器运行时配置 (Tailscale、网络、WiFi)
- [BUILD_EXPERIENCE.md](BUILD_EXPERIENCE.md) — 编译踩坑历史记录
- [ROUTER_STATE.md](ROUTER_STATE.md) — 设备分区/UBI/固件状态日志
- OpenWrt 主线: https://git.openwrt.org/openwrt/openwrt.git
- OpenClash: https://github.com/vernesong/OpenClash
- AX3000T 讨论: https://forum.openwrt.org/t/openwrt-support-for-router-home/180490

---

<!-- AGENT-MANAGED:START -->
> **Agent 维护区块**：本区块由 Agent 自动维护（规范 AGENTS.md §5），记录 Agent 项目状态入口。人工内容不受影响。

| 入口 | 说明 |
|---|---|
| [.agent/project-state.md](.agent/project-state.md) | 项目知识状态：已读证据、技术栈、入口、约定、未知项、核验时间、当前提交、推荐下一步 |
| [.agent/project-status.md](.agent/project-status.md) | 项目交接状态：当前状态、目标、已完成项、验证结果、已知问题、下一步、交接约束 |
| `.agent/plans/active/` | 当前任务计划（有明确任务时生成，task-id 默认 `YYYYMMDD-短英文任务名`） |
<!-- AGENT-MANAGED:END -->