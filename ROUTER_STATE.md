# 路由器当前状态记录 (AX3000T AN8855)

> 本文记录**实机上抓取的路由器信息**,用于后续刷机/编译排障参考,避免重复劳动。
> 最后更新:2026-08-14 | 数据来源:设备 SSH 实抓 + 刷机实测

---

## 0. 2026-08-14 刷机实测更新(重要)

**事件:** 按 README 流程 initramfs→`sysupgrade -n`(主线 stock 目标)迁移到官方双分区后,**重启进入原厂 U-Boot(恢复模式),未进入持久系统**。实测两次均如此。

**根因(已定位):**
- 主线 `main`(6.18)只有 `xiaomi_mi-router-ax3000t`(**双分区**:ubi_kernel@0x600000 + ubi@0x2800000)和 `-ubootmod` 两个目标,**没有独立的 `-an8855` 目标**(该目标只在 openwrt-24.10 分支存在)。
- 双分区布局对**原厂 U-Boot + AN8855 硬件**不友好:sysupgrade 后内核起不来/挂不上根,落回恢复页。
- 本机能持久跑的布局是 **24.10 官方 `-an8855` 目标:单 UBI 112MB @0x600000**(kernel+rootfs+rootfs_data 都在同一个 `ubi` 分区),原厂 U-Boot 认这套。

**已实施修复(2026-08-14,主线 main 上重建 an8855 单 UBI 目标):**

| 文件 | 改动 |
|------|------|
| `target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | **新建**,单 UBI `partition@600000 { label="ubi"; reg=<0x600000 0x7000000> }` |
| `target/linux/mediatek/image/filogic.mk` | 新增 `Device/xiaomi_mi-router-ax3000t-an8855`(initramfs-factory.ubi + squashfs-sysupgrade) |
| `.../filogic/base-files/lib/upgrade/platform.sh` | an8855 → `CI_UBIPART="ubi"` 单 UBI `nand_do_upgrade` |
| `.../filogic/base-files/etc/board.d/02_network` | 加 an8855 的 LAN/WAN(wan lan2-4)与 MAC(Bdata ethaddr_wan)规则 |
| `.config` | 目标切到 `CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y` |

**状态(2026-08-14 补充):** an8855 目标已编译出产物并**刷机成功**(initramfs→sysupgrade),
设备已能持久启动进入主线系统(主线 + LuCI 26)。

> ⚠️ **交接注意:** 以上 target 改动都在 `openwrt-ax3000t/`(OpenWrt mainline clone)**内部**,
> **不属于外层 GitHub 仓库**。若 `setup.sh` 重新克隆该目录,这些文件会丢失。
> 现已把改动固化到外层仓库 `patches/`,`setup.sh` 会自动重新打上,保证下次一键编译
> 一次通过、不再反复硬件调试。

**固化文件:**
- `patches/0001-add-an8855-target.patch` — filogic.mk 设备 + platform.sh 单 UBI + 02_network 网络/MAC
- `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` — 单 UBI `partition@600000 { label="ubi" }`

**补丁清单(与 mainline 内改动一一对应):**

| mainline 内文件 | 改动 |
|------|------|
| `target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | **新建**,单 UBI `partition@600000 { label="ubi"; reg=<0x600000 0x7000000> }` |
| `target/linux/mediatek/image/filogic.mk` | 新增 `Device/xiaomi_mi-router-ax3000t-an8855`(initramfs-factory.ubi + squashfs-sysupgrade) |
| `.../filogic/base-files/lib/upgrade/platform.sh` | an8855 → `CI_UBIPART="ubi"` 单 UBI `nand_do_upgrade` |
| `.../filogic/base-files/etc/board.d/02_network` | 加 an8855 的 LAN/WAN(wan lan2-4)与 MAC(Bdata ethaddr_wan)规则 |
| `.config` | 目标切到 `CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y` |

**OpenClash 显示问题(2026-08-14 定位):** 固件里其实有 OpenClash 文件,但 LuCI 菜单不显示。
根因 = 主线 **LuCI 26 移除 Lua**,OpenClash 是 Lua 应用,缺 `luci-compat`。修法见 README FAQ;
编译期在 `.config` 加 `CONFIG_PACKAGE_luci-compat=y`(+`luci-lua-runtime`),`setup.sh` 已自动加上。

**刷入流程(与原一致):** 恢复页/initramfs 刷 initramfs-factory.ubi → 内存系统 `sysupgrade -n` squashfs。

> 排障辅助事实:sysupgrade 写进 `ubi_kernel` 的 `kernel` 卷内容是合法 FIT(magic `d00dfeed`),
> 因此失败点不在"FIT 结构错误",而在双分区布局与原厂 U-Boot 的配合。内核 6.18 已开
> `CONFIG_MTD_ROOTFS_ROOT_DEV=y`(`.config:1523`),对单 UBI 中名为 `rootfs` 的 squashfs 卷
> 会自动建 ubiblock 并设根 —— 这是单 UBI 布局能持久自举的机制保障。

**当前设备:** 已刷主线持久系统(an8855 单 UBI)。**未砖**:按住 Reset 上电 → `192.168.31.1` 恢复页可重刷。

---

## 1. 设备概要

| 项目 | 值 |
|------|-----|
| 型号 | Xiaomi Mi Router AX3000T |
| 硬件版本 | **AN8855 外挂交换芯片版本**(非 MT7531) |
| SoC | MediaTek MT7981 (Filogic 820), aarch64 Cortex-A53 |
| 内存 | **256MB**(实抓 `Memory: 239088K/262144K`) |
| 闪存 | 128MB SPI-NAND |
| 当前 board_name | `xiaomi,mi-router-ax3000t-an8855` |
| 当前 U-Boot | **原厂 U-Boot**(非 OpenWrt U-Boot) |

## 2. 当前固件状态(升级前)

| 项目 | 值 |
|------|-----|
| 发行 | OpenWrt 24.10-SNAPSHOT (自定义编译) |
| 内核 | 6.6.138 |
| 目标 | mediatek/filogic, aarch64_cortex-a53 |
| 布局 | **自定义单 UBI 112MB**(非官方 stock 双分区) |
| root | squashfs on `/dev/root`, overlay = `ubi0_3`(vol rootfs_data) |
| `/proc/cmdline` | 空 |
| `/etc/fw_env.config` | **不存在**(uboot-envtools 未完整配置) |

> ⚠️ **重要:** 这台机器上跑的是旧仓库自定义固件(`-an8855` 单 UBI 布局),
> 与主线 stock/ubootmod 布局均不同,导致主线固件**无法直接 sysupgrade**(见 §5)。

## 3. 闪存分区 (`cat /proc/mtd`)

| mtd | 名称 | 大小    | 说明 |
|-----|------|---------|------|
| mtd0 | BL2       | 1MB  | 引导头 |
| mtd1 | Nvram     | 256KB | |
| mtd2 | Bdata     | 256KB | |
| mtd3 | Factory   | 2MB  | 含 EEPROM |
| mtd4 | FIP       | 2MB  | |
| mtd5 | crash     | 256KB | |
| mtd6 | crash_log | 256KB | |
| mtd7 | KF        | 256KB | |
| **mtd8** | **ubi** | **112MB (0x7000000)** | **系统分区(单 UBI)** |

擦除块 128KB (0x20000),页 2KB。

## 4. UBI 卷布局 (`ubinfo -a`)

UBI 设备: `ubi0`, LEB 126976 B (124 KiB), 896 LEB (108.5 MiB), 保留 17 个坏块 PEB。

| 卷 ID | 名称 | 大小 | 作用 |
|-------|------|------|------|
| 0 | `kernel`       | 4.2 MiB (35 LEB)   | 内核镜像 |
| 1 | `fit`          | 4.2 MiB (35 LEB)   | FIT 内核 |
| 2 | `rootfs`       | 25.6 MiB (212 LEB) | squashfs 只读根文件系统 |
| 3 | `rootfs_data`  | 71.5 MiB (591 LEB) | overlay (可写配置/数据) |

挂载关系:`/dev/root`(vol rootfs)→ `/rom` 只读,`ubi0_3` → `/overlay`。

## 5. 升级路径(重要结论)

**现状:** 单 UBI 112MB + 原厂 U-Boot + squashfs,board_name 是自定义 `...-an8855`。

**主线 stock 固件**(`xiaomi_mi-router-ax3000t`)是**双分区**(ubi_kernel+ubi),
与当前布局不兼容;sysupgrade 校验 board_name 也会拒绝。**不可直接 sysupgrade。**

**推荐流程(initramfs 过渡):**
1. 上传主线 `initramfs-factory.ubi` → `mtd -f write ... ubi` → `reboot`
   (进入主线内存系统,IP=192.168.31.1,WiFi 开放)
2. 在内存系统里 `sysupgrade -n` 主线 `squashfs-sysupgrade.bin`
   (自动迁移为官方双分区 + 写 mtdparts)
3. 完成后即成为**纯净主线 stock 布局**。

**救砖:** 断电 → 按住 Reset → 上电,进入原厂 U-Boot 恢复页 (192.168.31.1) 可重刷。

## 6. 常用排障速查

| 问题 | 排查 |
|------|------|
| 分区不符导致 sysupgrade 拒绝 | 先走 initramfs 过渡(§5),勿强刷 |
| `fw_printenv` 报 fw_env.config 缺失 | 当前固件未配 uboot-envtools;重刷主线后由 stock 升级脚本统一管理 |
| 需要确认 U-Boot 类型 | 原厂:Reset 恢复页可进 / 无 u-boot 定制;移动端看启动日志 |
| 想回到 stock 双分区 | 只有通过主线 initramfs→sysupgrade 流程自动达成 (§5) |

---

之后刷机/编译碰到任何"设备当前状态"问题,先看本文 §3-§5,不要重新上路由器抓。