# 项目状态

> **时间**：2026-08-17
> **作者**：Agent（按 AGENTS.md 自动维护）
> **适用范围**：openwrt-ax3000t-an8855
> **文档目的**：记录 Agent 对项目知识状态的核验结果与下一步
> **状态**：生效

## 常用入口

- 应用入口：`setup.sh`（一键构建入口）
- 开发命令：`bash setup.sh` / `bash setup.sh build`
- 构建命令：`make -j$(nproc) V=s`（在 openwrt-ax3000t/ 目录下）
- 测试命令：无标准测试套件，依赖实机刷机验证
- 文档入口：`README.md`、`ROUTER_STATE.md`、`BUILD_EXPERIENCE.md`
- Agent 规则入口：全局 `/Users/hugh/agent-config/AGENTS.md`
- 当前工作目录约定：`/Users/hugh/Documents/openwrt-ax3000t-an8855/`

## 核心模块

| 模块 | 路径 | 职责摘要 | 主要依赖 | 风险标签 | 最近变更 |
|---|---|---|---|---|---|
| 构建脚本 | `setup.sh` | 克隆 OpenWrt main、应用补丁、配置 feeds、生成 defconfig | git, patch, make | 高（漂移锁定） | 2026-08-15 |
| an8855 补丁 | `patches/` | 单 UBI 目标重建补丁，VERIFIED_COMMIT 锁定 | OpenWrt main DTS | 关键（启动布局） | 2026-08-14 |
| 文档 | `README.md`、`ROUTER_STATE.md`、`BUILD_EXPERIENCE.md` | 编译指南、实机状态、踩坑记录 | 无 | 中 | 2026-08-15 |
| 精简工具集 | `setup.sh` 预置配置 | 内核模块精选，控制 initramfs 体积 < 26MB | OpenWrt kmod | 高（体积上限） | 2026-08-14 |
| OpenClash 集成 | `setup.sh` 单独编译 | 编译为 apk 不进固件，避免体积超限 | OpenClash feed | 中 | 2026-08-15 |

## 验证命令

| 类型 | 命令 | 适用范围 | 预计副作用 | 最近结果 |
|---|---|---|---|---|
| 语法检查 | `bash -n setup.sh` | setup.sh | 无 | 未运行 |
| 补丁验证 | `patch --dry-run -p1 -i patches/0001-add-an8855-target.patch` | patches/ | 无 | 未运行 |
| 镜像体积校验 | `scripts/check-image-size.sh` | 编译产物 | 无 | 未运行 |
| Git 状态 | `git status` | 仓库 | 无 | 通过 |

## 已读证据
- README.md
- ROUTER_STATE.md
- BUILD_EXPERIENCE.md
- PROJECT.md
- setup.sh
- patches/0001-add-an8855-target.patch
- patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts
- patches/VERIFIED_COMMIT

## 技术栈
- OpenWrt main (内核 ≈ 6.18)
- MediaTek MT7981 (Filogic 820) / Airoha AN8855
- Buildroot / Makefile 构建系统
- Shell 脚本 (setup.sh, 补丁应用)
- UBI/UBIFS 文件系统布局

## 入口
- `setup.sh` — 主入口，支持 `--branch` 参数
- `patches/` — 补丁目录，含 VERIFIED_COMMIT 锁定
- `scripts/check-image-size.sh` — 镜像体积校验
- `README.md` — 用户文档入口

## 模块与约定
- 单 UBI 布局：`xiaomi_mi-router-ax3000t-an8855`（主线 stock 双分区不可用）
- VERIFIED_COMMIT 锁定防主线漂移
- OpenClash 单独编译为 apk（约 8MB），不进固件
- initramfs-FIT 体积必须 ≤ 26MB（原厂 U-Boot 限制）
- USTC apk 镜像加速国内下载
- 精简工具集：zram、iptables+nftables、wireguard、QoS、ext4、诊断工具

## 权威源
- 构建流程：`setup.sh`
- 补丁与目标：`patches/`
- 实机状态：`ROUTER_STATE.md`
- 踩坑记录：`BUILD_EXPERIENCE.md`
- 项目规划：`PROJECT.md`
- Agent 规则：全局 `/Users/hugh/agent-config/AGENTS.md`

## 当前任务
- 20260817-project-bootstrap（项目初始化与全局 Skills 体系验证）

## 未知项
- 无标准化测试/验证命令（CI/CD）
- 项目无独立 AGENTS.md，依赖全局配置
- OpenWrt 编译环境依赖外部主机（WSL2/Linux）

## 已知漂移
- 无

## 最后核验
- 2026-08-17

## 推荐下一步
- 运行 `validate-agent-state.sh` 验证状态文件完整性
- 可选：运行 `bash -n setup.sh` 验证脚本语法
- 可选：运行补丁 dry-run 验证补丁可应用性

## 快照元数据

- snapshot_version: 1
- generated_at: 2026-08-17
- base_commit: c1e0ce90fad4d59229a04be944d5a6e2b9985edf
- branch: master
- workspace_fingerprint: openwrt-build-project
- structure_fingerprint: single-repo-docs-patches-scripts
- last_incremental_sync: 2026-08-17
- changed_modules_since_snapshot: []
- cache_status: valid
- invalidation_reason: null