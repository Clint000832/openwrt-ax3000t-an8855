# OpenWrt Build for Xiaomi AX3000T (AN8855)

![CI Build](https://github.com/HughZadora/openwrt-ax3000t-an8855/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/HughZadora/openwrt-ax3000t-an8855/actions/workflows/release.yml/badge.svg)
![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg)

> **Date**: 2026-08-21
> **Author**: hugh
> **Scope**: infrastructure
> **Purpose**: Build OpenWrt mainline firmware for Xiaomi Mi Router AX3000T with AN8855 switch chip, including Tailscale and OpenClash support
> **Status**: active

## Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 2.0 | 2026-08-21 | hugh | Bilingual overhaul: English canonical README, consolidated DEVELOPMENT.md, architecture diagrams |
| 1.0 | 2026-08-15 | hugh | Initial Chinese-only documentation |

---

[English](#) | [中文](README.zh.md)

---

> Build OpenWrt mainline (kernel ≈6.18) for Xiaomi Mi Router AX3000T with AN8855 switch chip. Produces persistent single-UBI firmware compatible with stock U-Boot. Includes Tailscale in firmware, OpenClash as separate APK.

---

## Overview

- **Problem**: Xiaomi AX3000T (AN8855 variant) lacks official OpenWrt mainline target. Mainline only provides dual-partition target (`xiaomi_mi-router-ax3000t`) which fails to boot persistently on stock U-Boot with AN8855 hardware.
- **Why**: Stock U-Boot + AN8855 only supports single UBI partition layout (kernel+rootfs+rootfs_data in one `ubi` partition). Mainline dual-partition layout (`ubi_kernel` + `ubi`) causes bootloop to recovery mode.
- **Users**: Router owners wanting mainline OpenWrt on AX3000T AN8855; developers building custom firmware.
- **Core capabilities**:
  - Single-UBI target (`xiaomi_mi-router-ax3000t-an8855`) rebuilt on mainline via patches
  - One-command build via `setup.sh` (clones, patches, feeds, config)
  - Tailscale integrated in firmware for subnet routing
  - OpenClash as separate APK (avoids initramfs size limit)
  - Curated kernel module set (zram, iptables/nftables, wireguard, QoS, diagnostics) fitting <26MB initramfs

---

## Features

### Core
- **Single-UBI firmware target** — Rebuilt on OpenWrt mainline via `patches/`; compatible with stock U-Boot on AN8855 hardware
- **One-command build** — `bash setup.sh build` handles clone, patch, feeds, config, compile
- **Tailscale in firmware** — Pre-installed with `luci-app-tailscale-community`; advertises LAN subnet (`192.168.31.0/24`)
- **Curated kernel modules** — zram swap, iptables+nftables dual-stack, wireguard/veth/tun, QoS (cake/fq-pie), ext4, tcpdump/ipset/tc-full diagnostics — all within 26MB initramfs limit

### Optional
- **OpenClash as APK** — Compiled separately via `make package/feeds/openclash/luci-app-openclash/compile`; installed via `apk add luci-app-openclash` (auto-pulls `luci-compat`)
- **USTC package mirror** — Default `CONFIG_VERSIONOPT=y` + `CONFIG_VERSION_REPO=https://mirrors.ustc.edu.cn/openwrt/snapshots` for fast domestic downloads

### Experimental / Advanced
- **OpenWrt 24.10 branch support** — `bash setup.sh --branch openwrt-24.10 build` uses official AN8855 target (no patches needed)
- **Custom kernel/module selection** — Via `make menuconfig` after `setup.sh`

---

## Architecture

```mermaid
flowchart TD
    A[Developer Machine] -->|bash setup.sh build| B[OpenWrt Mainline Source]
    B --> C[Apply AN8855 Patches\npatches/0001-add-an8855-target.patch\npatches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts]
    C --> D[Update/Install Feeds\n+ OpenClash feed]
    D --> E[Generate .config\nan8855 target + Tailscale +\nCurated kmod set + USTC mirror]
    E --> F[Compile Firmware\nmake -j$(nproc) V=s]
    F --> G[Artifacts\ninitramfs-factory.ubi\nsquashfs-sysupgrade.bin\nOpenClash APK]
    G --> H[Router\nStock U-Boot + AN8855]
    H -->|1. mtd write initramfs| I[Initramfs RAM System]
    I -->|2. sysupgrade -n| J[Persistent OpenWrt\nSingle UBI Layout]
```

**Components**:
- `setup.sh` — Orchestrates clone, patch, feeds, config, optional build
- `patches/0001-add-an8855-target.patch` — Adds `xiaomi_mi-router-ax3000t-an8855` device to `filogic.mk`, single-UBI upgrade logic to `platform.sh`, network/MAC rules to `02_network`
- `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` — Device tree: single UBI partition `partition@600000 { label="ubi"; reg=<0x600000 0x7000000> }`
- `scripts/check-image-size.sh` — Validates initramfs FIT kernel ≤26MB (stock U-Boot load limit)

**Data flow**: Source → Patch → Feed → Config → Compile → Artifacts → Router (initramfs → sysupgrade)

**Core entry points**:
- `bash setup.sh` — Prepare source only
- `bash setup.sh build` — Prepare + full compile
- `bash setup.sh --branch openwrt-24.10 build` — Build on 24.10 stable branch

---

## Project Structure

```text
openwrt-ax3000t-an8855/
├── patches/
│   ├── 0001-add-an8855-target.patch      # filogic.mk + platform.sh + 02_network
│   ├── mt7981b-xiaomi-mi-router-ax3000t-an8855.dts  # Single UBI DTS
│   └── VERIFIED_COMMIT                   # Locked mainline commit SHA
├── scripts/
│   ├── check-image-size.sh               # Initramfs size validator
│   └── repository-check                  # Repository baseline validation
├── docs/                                 # Durable project docs (see docs/INDEX.yaml)
│   ├── development/guide.md              # Full developer guide
│   ├── operations/home-router.md         # Router runtime config (Tailscale, network)
│   ├── reports/build-experience.md       # Build troubleshooting archive
│   └── reference/router-state.md         # Device partition/UBI/firmware state log
├── openwrt-ax3000t/                      # OpenWrt source (gitignored, created by setup.sh)
├── setup.sh                              # One-command build orchestrator
├── README.md                             # This file (English)
├── README.zh.md                          # Chinese version
└── .agent/                               # Agent workspace state (auto-generated)
```

---

## Quick Start

### Prerequisites

- Linux x86_64 host (WSL2 supported)
- ≥8GB RAM (16GB+ recommended)
- ≥80GB free disk (first build ~40GB)
- SOCKS5 proxy for domestic users (`export ALL_PROXY=socks5h://host:port`)

### Install

```sh
# Clone this repository
git clone <this-repo-url>
cd openwrt-ax3000t-an8855

# (Domestic) Configure proxy for fast downloads
export ALL_PROXY=socks5h://your-proxy:port

# Prepare source + feeds + config (no build)
bash setup.sh

# Or: prepare AND build in one go
bash setup.sh build
```

### Run (Build)

```sh
# After setup.sh (if not using build mode)
cd openwrt-ax3000t

# Verify target profile selected
make menuconfig
# Target System: MediaTek Ralink ARM
# Subtarget: Filogic 820/830 (MT7981/MT7986)
# Target Profile: Xiaomi Mi Router AX3000T (AN8855)

# Compile (2–6 hours first run)
make -j$(nproc) V=s 2>&1 | tee build.log
```

### Verify Success

```sh
# Check artifacts
ls -lh bin/targets/mediatek/filogic/
# Expected:
# openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-an8855-initramfs-factory.ubi  (~25MB)
# openwrt-mediatek-filogic-xiaomi_mi-router-ax3000t-an8855-squashfs-sysupgrade.bin  (~27MB)
# OpenClash APK: bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash-*.apk
```

---

## Flashing to Router

> ⚠️ **Stock U-Boot + AN8855 requires single-UBI target.** Do NOT use stock `xiaomi_mi-router-ax3000t` (dual-partition).

### Method A: Initramfs → Sysupgrade (Recommended)

```sh
# 1. Flash initramfs (from stock/recovery)
scp bin/targets/.../openwrt-*-an8855-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1 'mtd -f write /tmp/openwrt-*-an8855-initramfs-factory.ubi ubi && reboot'

# 2. In RAM system (192.168.31.1), flash persistent sysupgrade
scp bin/targets/.../openwrt-*-an8855-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 'sysupgrade -n /tmp/openwrt-*-an8855-squashfs-sysupgrade.bin'
```

### Method B: Subsequent Upgrades

```sh
scp openwrt-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 'sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin'
```

### Post-Flash

- LAN: `192.168.31.1`, WiFi: `OpenWrt-AX3000T` / `OpenWrt-AX3000T-5G` (open)
- **Immediately set root password** and **configure WiFi encryption** in LuCI
- Install OpenClash: `scp <apk> root@192.168.31.1:/tmp/ && ssh root@192.168.31.1 'apk add /tmp/luci-app-openclash-*.apk && apk add luci-compat'`

---

## CI/CD Pipeline

This project uses **GitHub Actions** for automated builds and **semantic-release** for version management.

### Automated Builds

| Trigger | Branches | Artifacts |
|---------|----------|-----------|
| Push / PR | `master`, `openwrt-24.10` | Firmware (`.ubi`, `.bin`) + OpenClash APK |
| Daily (02:00 UTC) | `master`, `openwrt-24.10` | Same as above |
| Manual dispatch | Any | Same as above |

**Artifacts** are available for 90 days from the Actions tab. On successful `master` builds, the `VERIFIED_COMMIT` is automatically updated to the current OpenWrt commit SHA.

### Releases

Releases are automated via **semantic-release** on push to `master`:

1. Conventional commits (`feat:`, `fix:`, etc.) determine version bump
2. Changelog generated and committed
3. Git tag `vX.Y.Z` created
4. GitHub Release published with all firmware artifacts

See [guide.md#cicd-pipeline](docs/development/guide.md#cicd-pipeline) for full details.

---

## Development

See [guide.md](docs/development/guide.md) for complete build environment, customization, troubleshooting, and contribution guide.

### Common Commands

| Task | Command |
|------|---------|
| Prepare only | `bash setup.sh` |
| Full build | `bash setup.sh build` |
| Build on 24.10 | `bash setup.sh --branch openwrt-24.10 build` |
| Menuconfig | `cd openwrt-ax3000t && make menuconfig` |
| Clean build | `cd openwrt-ax3000t && make clean && make -j$(nproc) V=s` |
| Compile OpenClash APK | `cd openwrt-ax3000t && make package/feeds/openclash/luci-app-openclash/compile V=s` |
| Verify image size | `cd openwrt-ax3000t && ../scripts/check-image-size.sh` |

---

## Configuration

| File | Purpose |
|------|---------|
| `patches/VERIFIED_COMMIT` | Lock mainline commit for reproducible builds |
| `patches/0001-add-an8855-target.patch` | Target definition + upgrade + network patches |
| `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | Device tree (single UBI layout) |
| `setup.sh` | Build orchestration, branch selection, commit locking |
| `scripts/check-image-size.sh` | Initramfs FIT size validation (≤26MB) |

### Key Build Options (in `.config` after `setup.sh`)

| Option | Value | Purpose |
|--------|-------|---------|
| `CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855` | `y` | Single-UBI AN8855 target |
| `CONFIG_PACKAGE_luci-app-tailscale-community` | `y` | Tailscale LuCI app |
| `CONFIG_PACKAGE_luci-compat` | `y` | Lua runtime for OpenClash |
| `CONFIG_VERSIONOPT` | `y` | Enable version repo override |
| `CONFIG_VERSION_REPO` | `https://mirrors.ustc.edu.cn/openwrt/snapshots` | USTC mirror |

---

## Constraints & Limitations

- **Stock U-Boot only** — Requires single-UBI target; dual-partition stock target will bootloop
- **Initramfs ≤26MB** — Hard limit of stock U-Boot FIT loader; curated kmod set enforced
- **OpenClash not in firmware** — APK only; requires `luci-compat` (included in firmware)
- **AN8855 hardware only** — MT7531 variant uses different target (`xiaomi_mi-router-ax3000t`)
- **No USB/storage kmods** — Excluded to fit size budget; compile separately if needed

---

## Common Issues

| Issue | Solution |
|-------|----------|
| `fakeroot` deadlock | `kill -9 $(pgrep -f 'faked|fakeroot')` before rebuild |
| Download extremely slow | `export ALL_PROXY=socks5h://host:port` (git/curl native support) |
| `find: relative path in PATH` (WSL) | `PATH=$(echo "$PATH" \| tr ':' '\n' \| grep -v '^/mnt/' \| tr '\n' ':') make ...` |
| OpenClash menu missing | `apk add luci-compat && /etc/init.d/uhttpd restart` |
| Initramfs size check fails | Reduce kmods in `menuconfig`; check `scripts/check-image-size.sh` |
| Sysupgrade bootloops to recovery | Wrong target — must use `-an8855` single-UBI, not stock dual-partition |
| Kernel patch fails "No file to patch" | `setup.sh` uses `REPO_PATCH_DIR` (not `PATCH_DIR`) to avoid OpenWrt var collision |

---

## Contributing

1. Fork & branch
2. Test build: `bash setup.sh build`
3. Verify image size: `scripts/check-image-size.sh`
4. Update docs if user-facing changes
5. Open PR with conventional commit message

---

## License

GPL-2.0 — same as OpenWrt.

---

## Links

- [guide.md](docs/development/guide.md) — Complete build guide, troubleshooting, architecture
- [home-router.md](docs/operations/home-router.md) — Runtime router config (Tailscale, network, WiFi)
- [build-experience.md](docs/reports/build-experience.md) — Historical build troubleshooting
- [router-state.md](docs/reference/router-state.md) — Device partition/UBI/firmware state log
- OpenWrt mainline: https://git.openwrt.org/openwrt/openwrt.git
- OpenClash: https://github.com/vernesong/OpenClash
- AX3000T forum: https://forum.openwrt.org/t/openwrt-support-for-router-home/180490

---

<!-- AGENT-MANAGED:START -->
> **Agent Managed Block**: This block is auto-maintained by Agent (per AGENTS.md §5), recording Agent project state entry points. Human content unaffected.

| Entry | Description |
|---|---|
| [.agent/project-state.md](.agent/project-state.md) | Project knowledge state: evidence read, tech stack, entry points, conventions, unknowns, verification time, current commit, recommended next steps |
| [.agent/project-status.md](.agent/project-status.md) | Project handoff state: current state, goal, completed items, verification results, known issues, next steps, handoff constraints |
| `.agent/plans/active/` | Current task plan (generated when explicit task exists, task-id defaults to `YYYYMMDD-short-english-task-name`) |
<!-- AGENT-MANAGED:END -->