# Repository Guidelines

## Project Structure & Module Organization
- Source: `lua/nexus/**` organized by domain — `git/`, `render/`, `ui/`, `state/`, `actions/`, `providers/`.
- Entry: `plugin/nexus.lua` (guards load, defines `:Nexus`, auto‑open).
- Core: `lua/nexus/init.lua`; logging via `lua/nexus/logger.lua`.
- Tests: `tests/{unit,integration,performance}` with `tests/test_runner.lua` and `tests/minimal_init.lua`.
- Docs/Assets/Scripts: `docs/`, `assets/`, `scripts/`.

## Build, Test, and Development Commands
- `make test`: Run full headless suite (uses `plenary.test_harness`).
- `make test-unit|test-integration|test-performance`: Run by suite.
- `make test-file FILE=tests/unit/config_spec.lua`: Run one file.
- `make lint`: Luacheck; `make format` / `make format-check`: StyLua.
- `make watch`: Re-run tests on change; `make benchmark`: perf runs.
- `make deps`: Ensure `plenary.nvim` is installed for tests; `make clean`: remove artifacts.

## Coding Style & Naming Conventions
- Lua with 2-space indent; keep modules small and single-purpose.
- Filenames: `snake_case.lua`; modules return `M` table.
- Import with `require('nexus.*')`; avoid globals; prefer `nexus.logger`.
- Formatting/linting: run `make format` and `make lint` before PR.
- Place new features by domain (e.g., actions in `lua/nexus/actions/<area>/`).

## Testing Guidelines
- Framework: `plenary.test_harness` (Busted-style `describe`/`it`).
- Naming: `*_spec.lua`; put tests under `tests/unit` or `tests/integration`.
- Use `tests/helpers/mocks.lua` for git/fs/tmux stubs; avoid real I/O.
- Run `make test` locally; optional `make coverage` to spot gaps.

## Commit & Pull Request Guidelines
- Commits: Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`). Example: `feat: add commit amend popup`.
- PRs: clear description, linked issues, test updates, and screenshots/gifs for UI changes.
- Checks: `make test`, `make lint`, and `make format-check` must pass.
- Scope: focused diffs; update `README.md`/`docs/` when behavior changes.

## Security & Configuration Tips
- Shelling out: use wrappers in `nexus.git.operations`/`nexus.git.command`; avoid `os.execute`.
- Keep optional features behind config (e.g., `show_claude_conversations`).
- Startup: avoid blocking work; prefer `vim.defer_fn` for non-critical init.

