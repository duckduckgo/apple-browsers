# Feature map

How to reach and prove user-facing behavior of the macOS browser with `verify-macos-browser`. Read this index, then
the file for what you're proving. Each file lists every user entry point; a proof that drives one convenient entry
point is incomplete when the change touches others.

The map holds only features someone keeps current: a file here was filled from source and from proofs that pass. Add
a file only when you will maintain it, with a worked proof in `examples/`. An area with no file has no map yet: read
the source for its entry points, and write down what you learn in a new file if you'll keep it current.
`tests/test_features.py` fails when a file listed here is missing, a file isn't listed, or a file breaks the contract.

## Baseline preconditions

- The build is current: `prove` runs `doctor` and refuses a stale build.
- The app runs in English (`-AppleLanguages (en) -AppleLocale en_US`) as an internal user; `prove` passes both.
- Every flag the behavior depends on is pinned in the proof's `FLAGS`, on or off. Never rely on the live privacy
  configuration.
- In a VM, each run starts from a wiped Debug container with onboarding skipped (see Shared steps).

## Driving conventions

- Act through the user's path: the address bar, buttons, menus, keyboard shortcuts.
- Prefer AX identifiers from `AccessibilityIdentifiers` in `macOS/UITests/Common/XCUIApplicationExtension.swift`;
  then AX titles; coordinates last. `NSMenuItem`s get their action's selector name as AX id
  (`duckAIMenuSidebarAction`), and only exist in the tree while their menu is open.
- `url()` and `navigate()` (`AUTOMATION = True`) read the page URL and set up a page; they never stand in for the
  action under proof.
- Confirm each end state with a second, independent read (AX state, page URL, a log line, a pixel).
- An entry point you couldn't reach goes to the report's Unverified section, with why.

## Shared steps

The quirks every proof meets, so the harness steps that handle them have a spec. Change a step, change this list.

- **Skip onboarding.** A wiped container opens the Welcome tab. In a VM, `build` brings the app to the front, presses
  `MainMenu.skipOnboarding` (Debug → Skip Onboarding) and retries up to five times until a regular tab replaced the
  Welcome tab and the app is frontmost; otherwise it stops with `ONBOARDING NOT SKIPPED`. `--keep-onboarding` keeps
  it. On this Mac, nothing is wiped or skipped: the proof starts from whatever state the Debug app has.
- **Fresh state.** Duck.ai's own first-use state (accepted terms, chat history) lives in its web storage, which the
  VM wipe clears; on this Mac it doesn't, so a proof must not assume a first or a later visit.
- **Duck.ai terms.** When Duck.ai asks to accept its terms ("Continue"), in a tab or the sidebar, press Continue
  before the next step, unless the terms are what you're proving: until then Duck.ai doesn't answer. A wiped
  container (a VM run) gets them with the first prompt; on this Mac they may not show (Fresh state).
- **Find across windows.** `find`, `press` and `click` search the whole app: every window, the menu bar, and open
  menus and popovers. With a second window (a Duck.ai floating window, Cmd+N) the same id matches once per window
  and an action is refused as ambiguous; `tab_count()` counts tabs in every window. Pass `nth=` only after reading
  `find`'s output. A text query also matches by substring, so a short word ("Duck.ai") matches many elements.
- **Toggle memory.** The address bar's Search / Duck.ai mode belongs to the tab: once switched to Duck.ai, it stays
  across focus changes and tab switches until the tab submits, navigates or is switched back. Typed text in that
  tab goes to Duck.ai as a prompt; only one word that reads as a URL (no spaces) still navigates. Set up pages with
  `navigate()`, or switch back first, and give a prompt a space. Switching with text in the field carries the text
  over. The New Tab Page's own search box stores its last mode on disk and keeps it across launches.
- **Key-window popovers.** Keys inside an `NSPopover` (Esc, Return, Cmd+Return) only reach it while its window is
  key, and clicking the page takes that away. Press its buttons by AX id, or test the keys explicitly with the
  popover's window key. A popover that also answers keys from the browser window says so in its feature file.
- **Menus.** `click` the control that opens a menu, then `click` or `press` the item by its AX id. `key` sends the
  item's key equivalent instead, which is a different entry point: name the one you proved.

## File contract

Each file: an H1, one paragraph of user-visible behavior, then exactly these H2s in order:

- `Sub-features`: one line each, starting with a stable id in backticks (`duckai-tab-new-chat`) the report can cite.
- `How to get to it (user POV)`: every entry point, per sub-feature, with the AX ids and the flags or settings it
  needs.
- `Driving it`: starts with `Preconditions:` (flags, state, network), then per sub-feature how to act, what
  observable end state proves it, and which states are blocked and why. Names the worked proof and the XCUITests
  that already cover it.
- `Gotchas`: what made a check fail or mislead, and environment issues that aren't product bugs.

Keep implementation details out; name user paths, stable handles, required state and proof.

## Features

- Duck.ai
  - [Full tab](./duck-ai-tab.md): Duck.ai at duck.ai in a tab, opened from menus, the tab bar or the address bar's
    Duck.ai mode (example `t6_duckai_tab`).
  - [Sidebar](./duck-ai-sidebar.md): Duck.ai beside the page, with the page or selected text attached, its floating
    window, and browser tools (example `t7_duckai_sidebar`).
