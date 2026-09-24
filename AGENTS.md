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
| `project-structure.mdc` | Adding files or directories to the iOS project; buildable folders and Xcode groups |

## Testing against the Privacy Configuration

Do not write unit tests that assert the current state of the Privacy Configuration, such as whether a particular feature or flag is present, absent, enabled, or disabled. The Privacy Configuration is controlled remotely, so tests that rely on it too strongly may be affected.

Instead, arrange each relevant configuration state explicitly and verify the app's behavior in that state. Where applicable, verify behavior when flags are added or removed, enabled or disabled, or changed while the app is running.

## Opening a PR with snapshot changes

Before opening a monorepo PR, if the working tree has changes under the `SnapshotReferences` submodule, run `./scripts/open-snapshot-submodule-pr.sh` first, then add the submodule PR link it prints to the monorepo PR description.
