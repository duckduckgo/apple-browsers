# DuckDuckGo Apple browsers

Loaded into every agent session. Add a line only when agents demonstrably get
something wrong and nothing catches it during the task. Procedures live in
`.claude/skills/`; personal preferences live in your user-level config.

- Before finishing, run `mint run swiftlint lint --strict --force-exclude` on
  the files you changed. CI uses `--strict`, so any warning, including the
  file-header check, fails the PR; `--force-exclude` skips files CI doesn't
  lint, such as `Package.swift`.
- Every new Swift Testing `@Test` needs `.timeLimit(.minutes(1))`, which
  requires `@available(iOS 16, macOS 13, *)`.
- Adding, moving or deleting files in the Xcode projects: use the
  `ddg-xcode-add-file` skill.
- Adding or changing a pixel or wide event: use the `ddg-add-pixel` skill.
- Tests that depend on the remote Privacy Configuration arrange each flag
  state explicitly and assert the app's behavior in that state, including
  flags changing while the app runs. They never assert what the live
  configuration currently contains.
- Pull requests: fill in `.github/PULL_REQUEST_TEMPLATE.md`. If the
  `SnapshotReferences` submodule changed, run
  `./scripts/open-snapshot-submodule-pr.sh` first and add the PR link it
  prints to the description.
