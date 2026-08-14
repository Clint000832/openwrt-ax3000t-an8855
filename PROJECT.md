# Xiaomi AX3000T (AN8855) 路由器 / Tailscale 组网配置说明

## 项目目标

记录 `192.168.31.1` 这台 **Xiaomi Mi Router AX3000T（AN8855 交换机）** 的配置与交接要点，
重点是接入 Tailscale 组网、修复 fw4 对 tailnet 入站的处理，以及与办公室 `router-office`
节点互连。

## 设备与环境

- 型号：Xiaomi Mi Router AX3000T（AN8855 5 口千兆交换机）
- 系统：OpenWrt SNAPSHOT `r0-9f3157a`，架构 `aarch64_cortex-a53`
- Tailscale 节点：`router-home`，组网 IP **`100.10.0.1`**
- 登录：`ssh root@192.168.31.1`（本机 LAN）

## 网络拓扑与角色

- LAN：`br-lan` = `192.168.31.1/24`（桥接 `lan2/lan3/lan4`，即 AN8855 下游口）
- WAN：`wan@eth0`，DHCP 获取上行
  - 当前接在办公室网络 `192.168.110.x`：WAN IP `192.168.110.13`，网关 `192.168.110.1`
- 角色：家中路由器；同时是 Tailscale 组网节点，**通告子网 `192.168.31.0/24`**，
  使远端组网设备能经它访问家庭局域网。

## 关键配置

### Tailscale
- 节点 `router-home`，组网 IP `100.10.0.1`，状态：已登录、运行中
- 通告路由：`192.168.31.0/24`（供远端访问家庭网段）
- `RouteAll: true`（接受其它节点通告的路由）
- `CorpDNS: false`（**MagicDNS 关闭**，与办公室一致；访问用组网 IP 而非域名）
- `WantRunning: true`，开机自启
- 状态持久化：`/etc/tailscale/tailscaled.state`

### 网络（/etc/config/network）
- `br-lan`：`192.168.31.1/24`（桥接 `lan2/lan3/lan4`）
- `wan`：`eth0`，proto dhcp（上行到办公室 `192.168.110.x`）
- `tailscale0`：动态创建的 TUN 接口（不在 network 配置里，由 tailscaled 创建）

### 防火墙（firewall4 / nftables）
- 默认只有 `lan` / `wan` zone，**无 `tailscale` zone**
- 本机自身被组网访问：TCP 由 Tailscale 自带 `ts-input`（`iifname "tailscale0*" accept`）放行；
  但 **ICMP 会落入 fw4 默认 `handle_reject`**，表现为 `ping 组网IP` 返回
  `Destination Port Unreachable`（而 SSH 正常）。

## 关键修复：tailnet 入站 ICMP

### 症状
- 从组网其它节点（如 Ubuntu `dev`）`ssh root@100.10.0.1` 正常，
  但 `ping 100.10.0.1` 失败，返回 **`Destination Port Unreachable`**。

### 根因
`ts-input` 只对 tailscale0 的 TCP 短路放行，ICMP 未命中，继续走到 fw4 `input` 链
（该链无 `tailscale0` 跳转），落入默认 `handle_reject`，对非 TCP 协议返回
`reject` → ICMP `Destination Port Unreachable`。

### 修复（持久化）
与办公室 `router-office` 同套方案，新增 fw4 `config include` 脚本：
- 文件：`/etc/firewall-tailscale-input.sh`
  ```sh
  #!/bin/sh
  # 让 fw4 接受来自 tailnet (tailscale0) 进入本机(input)的流量
  nft insert rule inet fw4 input iifname "tailscale0" counter accept comment "Tailscale_input_accept"
  ```
- uci（`/etc/config/firewall`）：
  ```
  config include
  	option type 'script'
  	option path '/etc/firewall-tailscale-input.sh'
  ```
- 仅作用于 `tailscale0`，位于 `handle_reject` 之前，不影响 LAN/WAN。
- 修复后：`ping 100.10.0.1` 正常（0% 丢包，约 1.2ms，直连），SSH 仍正常。

## 使用方式

- 组网内任何节点访问本机：`ssh root@100.10.0.1`
- 远端访问家庭局域网设备：先确认手机/客户端开启 accept-routes 且子网路由
  `192.168.31.0/24` 已在控制台审批，再 `ssh root@192.168.31.x`。
- 因 MagicDNS 关闭，一律使用 IP。

## 常用命令（本机）

```sh
tailscale status                    # 组网状态
tailscale ping 100.10.0.1        # 控制面连通性
tailscale debug prefs | grep -i corp  # 确认 MagicDNS 关闭
/etc/init.d/tailscale restart
/etc/init.d/firewall reload
```

## 交接要点 / 坑

- **ICMP 被拒 ≠ SSH 被拒**：本机 SSH 正常但 ping 报 `Destination Port Unreachable`，
  即 fw4 `handle_reject` 兜底。修复靠上面的 include 脚本。
- **不要**改动 `CorpDNS` 开启 MagicDNS（需求要求关闭）。
- 该机默认无 `tailscale` zone：本机自身入站靠 `ts-input` + 上面脚本。
  若还要**远端访问家庭网内其它主机**（`192.168.31.x` 除本机外），需再补
  `tailscale` zone + `tailscale->lan` 转发（当前未配置）。
- WAN 断线会导致无默认路由、DNS 失败、Tailscale 无法登录控制面（表现为
  `tailscale status` 显示 logged out / NoState）。先保证 WAN 有链路。
- 遗留：防火墙配置里有一个失效的 `openclash` include（路径
  `/var/etc/openclash.include` 不存在），reload 时报警告，与组网无关，可清理。

## 与办公室节点互连

- 本机 `router-home`（100.10.0.1）与办公室 `router-office`（100.10.0.2）同账号组网。
- 本机 WAN 实际接在办公室网段 `192.168.110.x`，属"从家连到办公网络"的物理拓扑。

## 已知限制

- 远端访问家庭 LAN 内其它设备需子网路由审批 + 客户端 accept-routes，且本机需补 `tailscale` zone。
- 依赖家庭网络链路正常；WAN 掉线即失去外部可达性。
