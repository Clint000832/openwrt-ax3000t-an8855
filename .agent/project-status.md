# Project Status

> **Date**: 2026-08-21
> **Author**: Agent (auto-maintained per AGENTS.md)
> **Scope**: openwrt-ax3000t-an8855
> **Purpose**: Authoritative project handoff state — answers "what is the current project state, what to do next"
> **Status**: Active

## Current State

in-development — OpenWrt mainline build for Xiaomi AX3000T (AN8855) with Tailscale + OpenClash. Bilingual README + DEVELOPMENT.md complete. CI/CD pipeline planning in progress.

## Current Goal

Configure CI/CD pipeline (GitHub Actions) for automated builds with semantic-release and VERIFIED_COMMIT auto-update.

## Completed

- Single-UBI AN8855 target patches (patches/0001-add-an8855-target.patch, patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts)
- One-command build orchestrator (setup.sh) with branch selection and commit locking
- Curated kernel module set fitting <26MB initramfs limit
- Tailscale integrated in firmware; OpenClash as separate APK
- Bilingual README (English canonical + Chinese mirror) + consolidated DEVELOPMENT.md
- Agent bootstrap state (.agent/state.yaml, .agent/project-state.md)

## Key Technical Decisions

- Single-UBI target required for stock U-Boot + AN8855 compatibility (dual-partition stock target bootloops)
- Initramfs ≤26MB hard limit enforced by curated kmod selection
- OpenClash compiled as APK (not in firmware) to avoid size limit
- VERIFIED_COMMIT lock for reproducible mainline builds
- USTC mirror for fast domestic downloads
- Conventional Commits for git history

## Core File Changes

- setup.sh — build orchestration, branch selection, commit locking, patch application
- patches/0001-add-an8855-target.patch — target definition + upgrade logic + network rules
- patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts — single UBI partition device tree
- patches/VERIFIED_COMMIT — locked mainline commit SHA
- scripts/check-image-size.sh — initramfs FIT size validator (≤26MB)
- README.md / README.zh.md — bilingual user onboarding
- DEVELOPMENT.md — complete developer guide
- .agent/state.yaml — agent runtime state with task authorization

## Verification

| Type | Command | Recent Result | Status |
|---|---|---|---|
| Build | bash setup.sh build | Not run (CI/CD not configured) | not-run |
| Size Check | scripts/check-image-size.sh | Not run | not-run |
| Syntax | bash -n setup.sh | Not run | not-run |
| Doc Check | python3 gates/configuration/verify-project-documentation.py | Not run | not-run |

## Known Issues

- CI/CD pipeline not configured — no automated builds or release automation
- Automated firmware testing not implemented — relies on hardware flash verification
- Release automation not configured — no semantic versioning or changelog generation
- OpenClash APK requires manual compilation step

## Failed Approaches

- Using stock OpenWrt xiaomi_mi-router-ax3000t target (dual-partition) — bootloops on AN8855 hardware
- Including OpenClash in firmware — exceeds 26MB initramfs limit

## Next Steps

1. Configure CI/CD (GitHub Actions) for automated builds on push/PR
2. Add firmware validation framework
3. Implement release automation with semantic versioning
4. Consider adding hardware test automation

## Handoff Constraints

- Project is P1 classification (internal, non-sensitive arch, redacted test data)
- Build artifacts (firmware images) are P2 if containing production configs
- .env* and secrets/ are forbidden paths
- openwrt-ax3000t/ source directory is gitignored and forbidden for agent writes
- Agent writes allowed only in .agent/, .agents/, .github/workflows/, scripts/, patches/, README.md, DEVELOPMENT.md

---

> **Maintenance Rule**: Update this file on: task boundaries, major implementation phase complete, architectural decisions, verification status changes, blocker discovery/resolution, handoff, migration complete, experiment complete. Do not record trivial internal refactors, test implementations, formatting adjustments.