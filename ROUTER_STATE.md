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

---

## 7. 运行时配置(2026-08-14:网络 / DNS / Tailscale)

> 本节记录在**已刷入的主线持久系统**上手动配置的运行时状态,供交接与复现参考。

**SSH:** `ssh root@192.168.31.1`(当前可空密码或已配的密码登录)。

### 7.1 网络(`uci show network`)

| 项 | 值 |
|----|----|
| LAN 接口 | `br-lan`,static `192.168.31.1/24`,桥接端口 `lan2 lan3 lan4` |
| WAN 接口 | `wan`,proto `dhcp`(上游网络下发,实为 `192.168.110.x/24`) |
| WAN6 | `wan6`,proto `dhcpv6` |
| DHCP | 范围 `100~249`,租期 `12h`,`ra=server`,`dhcpv4/dhcpv6=server` |
| 防火墙 zone | lan: ACCEPT;wan: REJECT + masq |

### 7.2 DNS(`uci show dhcp.@dnsmasq[0]`)

- 上游 `server = 223.5.5.5, 114.114.114.114`(国内公共 DNS)
- `noresolv = 1`(忽略 WAN 下发,只用上面两个上游)
- **已移除** Tailscale 的 `/.ts.net/100.100.100.100` 转发(见下)
- 验证:`nslookup baidu.com 127.0.0.1` 正常解析

### 7.3 Tailscale(`uci show tailscale`)

| 键 | 值 | 说明 |
|----|----|------|
| `service_enabled` | `1` | 服务随开机自启 |
| `fw_mode` | `nftables` | 默认防火墙模式 |
| `dns_mode` | `disabled` | **禁用 MagicDNS**(不做 `.ts.net` 域名转发) |
| `accept_routes` | `1` | 接收组网内其他子网路由 |
| `advertise_exit_node` | `0` | 不充当出口节点 |
| `advertise_routes` | `192.168.31.0/24` | 子网路由,双向互通 |
| `nosnat` | `0` | 启用 SNAT(局域网访问组网走 NAT) |
| `ssh` | `1` | 允许 Tailscale SSH |

**当前节点:** `router-home`,Tailscale IP `100.10.0.1`,`tailscale status` 在线。

**开机自启(已确认 rc.d 软链):**
- `S80tailscale` → 启动 `tailscaled`(procd respawn,掉线自动拉起)
- `S99tailscale-settings` → 开机应用 `tailscale set` 设置与 DNS 转发维护
- `K10tailscale-settings` → 关机前清理

**运行逻辑:**
- 局域网设备(192.168.31.x)**无需自装 Tailscale**,直接访问组网设备(100.x.x.x)
  —— 依赖 `tailscale0` 接口 + `ts-forward` 链(收 lan→tailscale0)+ NAT SNAT。
- 组网远程设备**反向访问**局域网:靠 `advertise-routes=192.168.31.0/24`,
  **需在 Tailscale Admin 后台批准该子网路由**后才生效。
- MagicDNS 已禁用:不做 `.ts.net` 域名解析,一律按 IP 访问。

**复现命令(如需重配):**
```
uci set tailscale.settings.service_enabled=1
uci set tailscale.settings.dns_mode=disabled
uci set tailscale.settings.accept_routes=1
uci -q delete tailscale.settings.advertise_routes
uci add_list tailscale.settings.advertise_routes=192.168.31.0/24
uci commit tailscale
/etc/init.d/tailscale enable
/etc/init.d/tailscale-settings enable
/etc/init.d/tailscale start
/etc/init.d/tailscale-settings start
# 若节点未认证:tailscale up,登录 tailscale.com/a/xxx
```

## 8. 无线配置(2026-08-14:适配中国居民楼)

> 针对密集居民楼(邻居 WiFi 多、墙体厚)做的最优化配置。SSID 统一为 `OpenWrt-AX3000T`。

| 项 | 2.4GHz(radio0) | 5GHz(radio1) |
|----|----------------|--------------|
| 国家码 `country` | `CN` | `CN` |
| 信道 `channel` | **6**(扫描避开拥挤的 1/11) | **36**(HE80,中心 42) |
| 带宽 `htmode` | `HE20`(拥挤环境稳定优先) | `HE80`(用户选高带宽) |
| 发射功率 `txpower` | 20 dBm | 23 dBm |
| SSID | `MyHome` | `MyHome`(统一,自动选频) |
| 加密 `encryption` | `sae-mixed`(WPA3/WPA2) | `sae-mixed` |
| 密码 `key` | 已设(用户配置) | 同左 |
| 802.11k `ieee80211k` | 1 | 1 |
| 802.11v `ieee80211v` | 1 | 1 |

**选信道依据(实扫邻居):**
- 2.4GHz:信道 1(-36dBm)、11(-32dBm)干扰强,信道 6 相对干净(-81 以下)→ 选 6。
- 5GHz:149(-41dBm)干扰最强;36-48 中度(-55/-68)→ 保留 36(80MHz 非 DFS 中最优块)。

**⚠️ 踩坑记录(重要):**
- 开放(无加密)网络上**不能**启用 802.11r / ft_psk / mobility_domain / bss_transition,
  否则 hostapd 报 `1 errors found in configuration file` + `add_iface failed`,
  AP 不广播信道(`Channel: 0`)。
- **即使启用 WPA3(SAE) 加密,`sae-mixed` 下加 802.11r/ft_psk 仍会触发同一 hostapd 错误**。
  本设备为单 AP,802.11r 快速漫游本用于多 AP 无缝漫游,单机收益极小,故**保持关闭**。
- 正确做法:仅保留 802.11k / 802.11v(辅助漫游与选频),不开 r/ft。

**复现命令:**
```
uci set wireless.radio0.country=CN; uci set wireless.radio1.country=CN
uci set wireless.radio0.channel=6;    uci set wireless.radio1.channel=36
uci set wireless.radio0.htmode=HE20;  uci set wireless.radio1.htmode=HE80
uci set wireless.radio0.txpower=20;   uci set wireless.radio1.txpower=23
uci set wireless.default_radio0.ssid=OpenWrt-AX3000T
uci set wireless.default_radio1.ssid=OpenWrt-AX3000T
uci set wireless.default_radio0.ieee80211k=1
uci set wireless.default_radio0.ieee80211v=1
uci set wireless.default_radio1.ieee80211k=1
uci set wireless.default_radio1.ieee80211v=1
uci commit wireless; wifi down; wifi up
```

> ⚠️ **已知限制:** 从路由器 `ping` 组网内其他节点,常规 ICMP 可能 100% 丢包
> (对端如 router-office 的入站 ICMP 过滤所致),但 `tailscale ping` 通、TCP/UDP 正常,
> 属对端策略,不影响本机 LAN→组网访问。

---

## 9. 7×24 稳定性调优(2026-08-14)

> 针对家庭路由器长期不间断运行所做的调优。**已确认**:无 OOM/崩溃历史、看门狗正常、
> 内存健康、WiFi 双频在线、Tailscale 在线。

### 9.1 已实施的内核参数(`/etc/sysctl.d/99-stability.conf`,重启持久)

| 参数 | 值 | 作用 |
|------|----|------|
| `vm.swappiness` | `10` | 减少内存换页压力,进程更稳定 |
| `net.core.netdev_max_backlog` | `4096` | 应对网络突发,降低丢包 |
| `net.core.somaxconn` | `4096` | 提高连接队列 |
| `net.ipv4.tcp_slow_start_after_idle` | `0` | 空闲后不重置慢启动,游戏/视频更稳 |
| `net.netfilter.nf_conntrack_max` | `32768` | 容纳更多家庭设备连接(当前仅用 ~59) |
| `net.netfilter.nf_conntrack_tcp_timeout_established` | `3600` | 缩短过期连接,防 conntrack 表满 |
| `net.netfilter.nf_conntrack_udp_timeout` | `60` | 同上 |
| `net.netfilter.nf_conntrack_icmp_timeout` | `10` | 同上 |
| `kernel.panic` | `3` | 内核异常 3 秒自动重启(不死机) |
| `kernel.panic_on_oops` | `1` | oops 触发重启而非挂死 |

### 9.2 硬件看门狗(已确认)

- `procd` 正在喂 `/dev/watchdog`:timeout 30s,每 5s 喂一次,`magicclose=false`。
- 系统**卡死会自动复位重启**,无需人工干预 → 7×24 不下线的关键保障。

### 9.3 关键服务状态(已确认运行 + procd respawn)

| 服务 | 状态 | 说明 |
|------|------|------|
| `dnsmasq` | OK | DNS/DHCP,1.4MB |
| `odhcpd` | OK | IPv6/DHCPv6 |
| `hostapd` | OK | WiFi(2.8MB) |
| `netifd` | OK | 网络接口管理 |
| `tailscaled` | OK + respawn | Tailscale,76MB(最大,正常),procd 掉线自动拉起 |

**内存画像:** 256MB 总内存,~42MB 可用;日志走 RAM(`/tmp`,tmpfs)不写闪存,减少 NAND 磨损。

### 9.4 刻意不做的操作(避免伤害稳定/闪存)

- **不在 NAND 上建 swap**:swap 频繁写会加速闪存磨损 → 放弃。
- **zram 交换**:此自定义 SNAPSHOT 固件无 zram 内核模块/包,无法启用 → 放弃。
- **定时重启**:用户要求"不下线",故**不设**每日/每周自动重启(内存现状无需)。

### 9.5 后续维护建议

- 定期(如每周)`ssh root@192.168.31.1 'tailscale status; uptime; free'` 抽查内存与负载。
- 若某日 `free` 显示 available 持续 <20MB,优先排查 tailscaled 是否内存泄漏(重启该服务即可)。
- 固件升级走 §5 initramfs→sysupgrade 流程,勿强刷。