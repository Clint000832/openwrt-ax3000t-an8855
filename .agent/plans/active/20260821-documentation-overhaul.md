# L1 标准授权包：documentation
# 任务：文档全面改造 - 双语 README + 合并 DEVELOPMENT.md + 架构图

task_id: "20260821-documentation-overhaul"
task_type: documentation
title: "Documentation Overhaul: Bilingual README + Consolidated DEVELOPMENT.md + Architecture Diagrams"
base_commit: "5f04e08b8660c0df6f94c4483642f8ebea140da3"
branch: "main"
created_at: "2026-08-21"
expires_at: "2026-08-28"

objective: "Transform project documentation to meet AGENTS.md §16 standards: bilingual README (English + Chinese) with language selector, consolidated DEVELOPMENT.md merging all existing docs, and Mermaid architecture/build flow diagrams. Pass verify-project-documentation.py gate."

acceptance_criteria:
  - "README.md exists as English canonical version with language selector linking to README.zh.md"
  - "README.zh.md exists as Chinese version mirroring English content, kept in sync"
  - "DEVELOPMENT.md created consolidating PROJECT.md, BUILD_EXPERIENCE.md, ROUTER_STATE.md content"
  - "README follows readme-design-baseline.md structure (quick start, architecture, features, config, troubleshooting)"
  - "DEVELOPMENT.md contains full setup, build process, troubleshooting, architecture details"
  - "Mermaid diagrams for build pipeline and firmware architecture included"
  - "No duplicate content between README and DEVELOPMENT.md (README links to DEVELOPMENT.md)"
  - "verify-project-documentation.py gate passes (bilingual README present, DEVELOPMENT.md present, no duplication, AGENT-MANAGED block in README, language selector)"
  - "All existing factual information preserved and verified against current project state"

allowed_read_paths:
  - "README.md"
  - "README.zh.md"
  - "PROJECT.md"
  - "BUILD_EXPERIENCE.md"
  - "ROUTER_STATE.md"
  - "setup.sh"
  - "patches/"
  - "scripts/"
  - ".config/opencode/templates/project-infrastructure/readme-design-baseline.md"
  - ".config/opencode/templates/project-infrastructure/DEVELOPMENT.md"

allowed_write_paths:
  - "README.md"
  - "README.zh.md"
  - "DEVELOPMENT.md"
  - ".agent/plans/active/20260821-documentation-overhaul.md"

forbidden_paths:
  - ".env*"
  - "**/secrets/**"
  - "**/migrations/**"
  - "package.json"
  - "lockfiles"
  - "openwrt-ax3000t/"
  - "patches/*.dts"
  - "scripts/check-image-size.sh"

risks:
  - "Content drift: existing docs may have outdated info vs current project state"
  - "Duplication: must ensure README and DEVELOPMENT.md don't overlap per AGENTS.md §16.2"
  - "Verification: verify-project-documentation.py gate must pass"

sensitive_data_assessment: "P0/P1 only"

validation_commands:
  - "python3 .config/opencode/gates/configuration/verify-project-documentation.py"
  - "git diff --stat"

expected_validation_result: "All verification checks pass; bilingual README present and in sync; DEVELOPMENT.md present; no duplication; language selector present; AGENT-MANAGED block intact"

max_changed_files: 3
max_diff_lines: 500
max_fix_rounds: 3
max_tool_calls: 30

rollback_or_revert_strategy: "git revert <commit>"
commit_required: true
commit_scope_rule: "only files within allowed_write_paths"

documentation_impact:
  level: "DOC_MULTIPLE"
  reviewed: false
  reason: "Creates/modifies README.md, README.zh.md, DEVELOPMENT.md - all core documentation entry points"

doc_entry_points:
  - "README.md"
  - "README.zh.md"
  - "DEVELOPMENT.md"
target_audience: "OpenWrt builders, router owners, developers, contributors"
fact_sources:
  - "README.md (current)"
  - "PROJECT.md"
  - "BUILD_EXPERIENCE.md"
  - "ROUTER_STATE.md"
  - "setup.sh"
  - "patches/"
prohibited_sensitive_content: "P2/P3 data, internal IPs, credentials, customer data"