# Project State

> **Date**: 2026-08-21
> **Author**: Agent (auto-maintained per AGENTS.md)
> **Scope**: openwrt-ax3000t-an8855
> **Purpose**: Record Agent knowledge state verification results and next steps
> **Status**: active

## Common Entry Points

- Build entry: `setup.sh` (one-command build)
- Dev commands: `bash setup.sh` / `bash setup.sh build`
- Build command: `make -j$(nproc) V=s` (in openwrt-ax3000t/ directory)
- Test command: No standard test suite; relies on hardware flash verification
- Documentation entry: `README.md`, `README.zh.md`, `DEVELOPMENT.md`, `ROUTER_STATE.md`, `BUILD_EXPERIENCE.md`
- Agent rules entry: Global `/home/hugh/agent-config/AGENTS.md`
- Current working directory: `/home/hugh/Projects/openwrt-ax3000t-an8855/`

## Core Modules

| Module | Path | Responsibility | Key Dependencies | Risk Level | Last Changed |
|--------|------|----------------|------------------|------------|--------------|
| Build script | `setup.sh` | Clone OpenWrt main, apply patches, configure feeds, generate defconfig | git, patch, make | High (drift lock) | 2026-08-18 |
| AN8855 patches | `patches/` | Single UBI target rebuild patches, VERIFIED_COMMIT lock | OpenWrt main DTS | Critical (boot layout) | 2026-08-14 |
| Documentation | `README.md`, `README.zh.md`, `DEVELOPMENT.md`, `ROUTER_STATE.md`, `BUILD_EXPERIENCE.md` | Build guide, device state, troubleshooting archive | None | Medium | 2026-08-21 |
| Curated kmod set | `setup.sh` defconfig | Kernel module selection, controls initramfs size < 26MB | OpenWrt kmod | High (size limit) | 2026-08-14 |
| OpenClash integration | `setup.sh` separate compile | Compile as APK not in firmware, avoids size limit | OpenClash feed | Medium | 2026-08-15 |

## Verification Commands

| Type | Command | Scope | Side Effects | Last Result |
|------|---------|-------|--------------|-------------|
| Syntax check | `bash -n setup.sh` | setup.sh | None | Not run |
| Patch validation | `patch --dry-run -p1 -i patches/0001-add-an8855-target.patch` | patches/ | None | Not run |
| Image size check | `scripts/check-image-size.sh` | Build artifacts | None | Not run |
| Git status | `git status` | Repository | None | Pass |
| Doc verification | `python3 .config/opencode/gates/configuration/verify-project-documentation.py` | All docs | None | Not run |

## Evidence Read

- README.md (new bilingual)
- README.zh.md (new Chinese mirror)
- DEVELOPMENT.md (new consolidated)
- ROUTER_STATE.md
- BUILD_EXPERIENCE.md
- PROJECT.md
- setup.sh
- patches/0001-add-an8855-target.patch
- patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts
- patches/VERIFIED_COMMIT

## Tech Stack

- OpenWrt main (kernel ≈ 6.18)
- MediaTek MT7981 (Filogic 820) / Airoha AN8855
- Bash build orchestration
- Mermaid diagrams in README

## Conventions

- Conventional Commits for git history
- Bilingual README (English canonical + Chinese mirror)
- README = user onboarding; DEVELOPMENT.md = developer guide
- No duplication between README and DEVELOPMENT.md
- AGENT-MANAGED block at end of README files

## Unknowns

- CI/CD pipeline not yet configured
- Automated firmware testing not implemented
- Release automation not configured

## Verification Time

- Last verified: 2026-08-21
- Verified commit: 5f04e08b8660c0df6f94c4483642f8ebea140da3

## Recommended Next Steps

1. Configure CI/CD (GitHub Actions) for automated builds
2. Add firmware validation framework
3. Implement release automation with semantic versioning
4. Consider adding hardware test automation