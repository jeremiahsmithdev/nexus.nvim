# Nexus.nvim Documentation Index

Central directory for all Nexus.nvim documentation. If a file is not
listed here, either index it or consolidate it into an existing entry —
orphaned docs are not maintained.

## Quick Reference

| Feature | Doc | Last Updated | Status |
|---------|-----|--------------|--------|
| Dashboard lifecycle (two-phase render) | [dashboard-lifecycle.md](./dashboard-lifecycle.md) | 2026-04-16 | current |
| Git pipeline (single-subprocess batch) | [git-pipeline.md](./git-pipeline.md) | 2026-04-16 | current |
| Beads integration (async, SWR) | [beads-integration.md](./beads-integration.md) | 2026-04-16 | current |
| Folding (section + overflow) | [folding.md](./folding.md) | 2026-04-16 | current |
| Logo system (dispatcher + variants) | [logo-system.md](./logo-system.md) | 2026-04-16 | current |
| Git command reference | [git-commands.md](./git-commands.md) | unknown | needs-review |
| Linear integration (implementation) | [LINEAR_IMPLEMENTATION.md](./LINEAR_IMPLEMENTATION.md) | unknown | needs-review |
| Linear git project linking | [linear-git-project-linking.md](./linear-git-project-linking.md) | unknown | needs-review |
| Linear — GraphQL API notes | [linear/GraphQL-API.md](./linear/GraphQL-API.md) | unknown | current |
| Linear — OAuth2 flow | [linear/OAuth2.md](./linear/OAuth2.md) | unknown | current |
| Linear — usage guide | [linear/Guide-linear.new.md](./linear/Guide-linear.new.md) | unknown | current |
| Performance principles (guide) | [performance.md](./performance.md) | unknown | needs-review |
| Technical specifications | [TECHNICAL_SPECIFICATIONS.md](./TECHNICAL_SPECIFICATIONS.md) | unknown | needs-review |

### Decisions (ADRs)

| ID | Title | Status |
|----|-------|--------|
| 001 | [Two-phase async startup render](./decisions/001-async-startup-two-phase-render.md) | accepted |
| 002 | [Stale-while-revalidate for beads CLI](./decisions/002-stale-while-revalidate-beads.md) | accepted |
| 003 | [Prefer extmarks over `nvim_buf_add_highlight`](./decisions/003-extmark-over-nvim-buf-add-highlight.md) | accepted |

### Deprecated / Historical

Kept for reference but no longer reflects the current codebase. Do not
update these files — update the live docs and ADRs instead.

| Doc | Why retained | Status |
|-----|--------------|--------|
| [CLAUDE-PLAN.md](./CLAUDE-PLAN.md) | Early planning doc | deprecated |
| [IMPLEMENTATION_ROADMAP.md](./IMPLEMENTATION_ROADMAP.md) | Historical roadmap | deprecated |
| [PRE_LINEAR_REFACTORING_PLAN.md](./PRE_LINEAR_REFACTORING_PLAN.md) | Pre-Linear refactor plan | deprecated |
| [PERFORMANCE_ANALYSIS.md](./PERFORMANCE_ANALYSIS.md) | Input to T1–T18 perf pass; captures prior state | deprecated |
| [PERFORMANCE_OPPORTUNITIES.md](./PERFORMANCE_OPPORTUNITIES.md) | Input to T1–T18 perf pass | deprecated |
| [COLLAPSIBLE_SECTIONS.md](./COLLAPSIBLE_SECTIONS.md) | Superseded by [folding.md](./folding.md); duplicates root-level file | deprecated |

## Categories

### Core Features
- [Dashboard Lifecycle](./dashboard-lifecycle.md)
- [Git Pipeline](./git-pipeline.md)
- [Folding](./folding.md)
- [Logo System](./logo-system.md)

### Integrations
- [Beads](./beads-integration.md) — local git-backed issue tracker
- [Linear — Implementation](./LINEAR_IMPLEMENTATION.md)
- [Linear — Git project linking](./linear-git-project-linking.md)
- [Linear — GraphQL API](./linear/GraphQL-API.md)
- [Linear — OAuth2](./linear/OAuth2.md)
- [Linear — Guide](./linear/Guide-linear.new.md)

### Utilities
- [Git Commands](./git-commands.md) — command reference

### Architecture
- [Performance principles](./performance.md)
- [Technical specifications](./TECHNICAL_SPECIFICATIONS.md)

### Decisions
- [001 — Two-phase async startup render](./decisions/001-async-startup-two-phase-render.md)
- [002 — Stale-while-revalidate for beads](./decisions/002-stale-while-revalidate-beads.md)
- [003 — Extmarks over `nvim_buf_add_highlight`](./decisions/003-extmark-over-nvim-buf-add-highlight.md)

## Status Values

- **current** — up to date, maintained
- **needs-review** — implementation may have drifted; re-validate before trusting
- **outdated** — known to be out of sync
- **deprecated** — feature removed/replaced, kept for history

## Maintenance Log

- **2026-04-16** — Created INDEX.md. Added five feature docs
  (`dashboard-lifecycle`, `git-pipeline`, `beads-integration`, `folding`,
  `logo-system`) and three ADRs (001–003) covering the T1–T18
  performance refactor pass. Marked legacy plans and pre-refactor
  performance analyses as deprecated.

## Huly Integration

Huly is not documented here because it is dormant (see `T14`; the provider
assumes GraphQL but Huly speaks WebSocket — awaiting a Node bridge).
Status is tracked in `HULY_INTEGRATION_STATUS.md` at the repo root, kept
outside of the versioned docs tree until the integration is re-activated.
