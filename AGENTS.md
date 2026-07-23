This file configures AI coding assistants for the Apple monorepo.
Development rules are maintained in `.cursor/rules/` as the single source of truth.

**Personal preferences** (workflow, communication style, tool settings) belong in
your tool's user-level config, not here:
- Claude Code: `~/.claude/CLAUDE.md`
- Cursor: User-level settings

This repo-level file is for **team-shared conventions only**.

## Mandatory Rules

Detailed rules live in `.cursor/rules/`. Read from the list below when the request is relevant. **Do not read any other files in `.cursor/rules` unless requested explicitly.**

| File | Covers |
|------|--------|
| `general.mdc` | Project overview, architecture summary, rule index, quick-start checklists |
| `code-style.mdc` | Full Swift style guide: naming, formatting, closures, optionals, memory management |
| `anti-patterns.mdc` | What NOT to do: singletons, async mistakes, SwiftUI pitfalls, testing mistakes |
| `user-defaults-storage.mdc` | Storing settings or preferences via `KeyValueStore` |
| `pixels.mdc` | Defining, naming, or firing pixel events |

## Cursor Cloud specific instructions

The Cursor Cloud VM runs **Linux**, but this is a macOS/Xcode monorepo (Xcode `26.4`, see `.xcode-version`).

- **Cannot run on the Linux cloud VM:** building/running the iOS or macOS browser apps, SwiftLint, and all Swift unit/UI/integration tests. These require macOS + Xcode and run only on macOS CI runners. The build/lint/test commands are documented in `.cursor/rules/development-commands.mdc` and `.cursor/rules/testing.mdc`; do not attempt them here. There is no Swift toolchain installed (only `clang`).
- **Does run on Linux** (this is the full cross-platform dev surface here, and mirrors the only `ubuntu-latest` CI job, `Pixel Schema Validation`):
  - Autoconsent bundle rebuild: `npm run rebuild-autoconsent` (i.e. `rollup -c`), run **from inside `iOS/` or `macOS/`**. It regenerates `DuckDuckGo/Autoconsent/autoconsent-bundle.js`.
  - Pixel tooling, run from inside `iOS/` or `macOS/`: `npm run pixel-lint`, `npm run validate-defs-without-formatting`, `npm run check-wide-events`. (CI additionally passes `-g` a user map from the private `internal-github-asana-utils` repo, which is not needed for local validation.)
- **Non-obvious gotchas:**
  - `rollup` and its plugins live in the **repo-root** `node_modules` (root `package.json` holds `@duckduckgo/autoconsent` + rollup), while the pixel tools resolve from `iOS/node_modules` / `macOS/node_modules`. So dependency setup is three installs: repo root, `iOS/`, and `macOS/`.
  - Running `npm ci` in a platform dir rebuilds the shared repo-root `node_modules`. Do **not** run a rollup build concurrently with any `npm ci` — it fails with a `rollup-plugin-terser` require-stack error. Run them sequentially.
  - `validate-defs-without-formatting` regenerates tracked files under `PixelDefinitions/wide_events/generated_schemas`; they reproduce identically, so a clean run leaves the git tree clean.
