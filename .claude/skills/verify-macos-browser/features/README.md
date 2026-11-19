# Feature map

How to reach and prove user-facing behavior of the macOS browser with `verify-macos-browser`. Read
this file, then the file for the area you're changing. Each file lists every user entry point; a
check that drives one convenient entry point is incomplete when the change touches others.

## Baseline preconditions

- The build is current: `verify.sh doctor <topic>` prints `OK`.
- The app runs in English (`-AppleLanguages (en) -AppleLocale en_US`) as an internal user; `build`
  passes both.
- Every flag the behavior depends on is pinned with `verify.sh flag`, on or off. Never rely on the
  live privacy configuration.

## Driving conventions

- Act through the user's path: the address bar, buttons, menus, keyboard shortcuts.
- Prefer AX identifiers from `AccessibilityIdentifiers` in
  `macOS/UITests/Common/XCUIApplicationExtension.swift`; then AX titles; coordinates last.
- `verify.sh web` (with `build --automation`) reads the page URL and values; it never acts.
- Shortcuts inside an `NSPopover` fire only when its window is key.
- Confirm each end state with a second, independent read (AX state, page URL, a log line, a pixel).
- An entry point you couldn't reach goes to the report's Unverified section, with why.

## File contract

Each file: an H1, one paragraph of user-visible behavior, then exactly these H2s in order:

- `Sub-features`: one line each, with a stable id (`duckai-toggle`) the report can cite.
- `How to get to it (user POV)`: every entry point, per sub-feature.
- `Driving it`: starts with `Preconditions:` (flags, state, network), then per sub-feature how to
  act and what observable end state proves it.
- `Gotchas`: what made a check fail or mislead, and environment issues that aren't product bugs.

Keep implementation details out; name user paths, stable handles, required state and proof.

## Areas

| Area | File |
|---|---|
| Duck.ai (omnibar toggle, sidebar, full tab, browser tools) | duck-ai.md |
| New Tab Page | new-tab-page.md |
| Omnibar / address bar | omnibar.md |
| Tabs and windows | tabs.md |
| Settings | settings.md |

Files other than Duck.ai hold only headings; fill each on its first real run.
