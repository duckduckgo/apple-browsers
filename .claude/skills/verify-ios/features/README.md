# DuckDuckGo iOS verification map

The maintained source for verifying user-facing behavior of the DuckDuckGo iOS browser with `verify-ios`. Read this
index, then the feature file for what you are proving. Each feature lists every user entry point on iPhone and iPad;
a proof that drives one convenient entry point is incomplete when the file lists others that the change touches.

This map is also the specification for `lib/verify_ios/steps.py`: every quirk a step handles is written down here,
so the steps can be ported to Swift from this map when the app's XCUITest UI tests want them.

## Baseline preconditions

- `V=.claude/skills/verify-ios/bin/verify-ios`, run from the root of the worktree under test.
- The app build is current (`$V build --app-only` after app changes; `prove` refuses a stale build). `prove` creates
  the simulator it needs and deletes it when it ends.
- Every proof starts from a known state with `steps.fresh_start(ios)`: reinstalled app, onboarding skipped, one
  blank tab with the address bar not focused, no site data or permissions, daily pixel state cleared.
- Feature flags are pinned, never taken from the live privacy configuration: every launch pins
  `env.PINNED_FLAGS` (`newTabPageRedesign: true`; the iPhone new-tab page's Duck.ai button `Browser.OmniBar.Button.AIChat`
  exists only with it). The unified toggle input (`UnifiedToggleInput.*`, `AIChat.Toolbar.Button.Submit`) is not
  flag-gated: it is on for every iPhone and off on iPad. A proof that needs another flag sets `FLAGS`.
- Pages to drive come from the local fixture (`ios.fixture_url(token)`), with a fresh token per run.

## Driving conventions

- Act only through native locators (`id=`, `label=`, `role=`, `text=`, `nth=`). `web:*` locators read; they never act.
- Use the user's path for the behavior under proof. `ios.navigate` / `ios.eval` are setup and read-back only.
- `ios.navigate` fails on the new-tab page (it has no web view): load the first page through the address bar.
- Many controls are labelled with their **icon asset name**, not words: `Add 24`, `Fire Solid 24`, `Share Apple 24`
  (on `Browser.OmniBar.Button.Customizable`). Prefer `id=` where one exists; use these labels where none does (the
  iPad Fire button, the icon-layout tab switcher's `Add 24`).
- The app is single-scene (`UIApplicationSupportsMultipleScenes = false`): there is no second iPad window.
- When a locator is ambiguous, pick with `nth=` only after checking `find` output; the iPad tab bar and switcher
  expose the same tab label twice and one copy is covered.
- Pixel names end in `_ios_phone` or `_ios_tablet`: use `ios.form_factor`.
- The address bar and toolbar are Liquid Glass: they take their tint from the content underneath, so in dark mode
  they only look dark over a dark page. The fixture page follows the system appearance for that reason.

## Proof and skip reporting

- `prove` captures the transcript, final screenshot and tree, pixels and wide events; take your own `ios.shot` before
  and after each key action.
- Confirm the end state with a second, independent read (URL or page value from the web channel, tab count from the
  native tree, keyboard/focus state, a pixel or wide event).
- Record the device, the feature sub-ID and the entry point in the proof's docstring or `ios.note`.
- Report an entry point you could not reach with `ios.unverified(what, why)`. Never report it as verified through
  another path.
- Environment failures (see each file's Gotchas) are reported as environment, not as product bugs.

## Feature entry contract

Each file: an H1, one paragraph of user-visible behavior, then exactly these H2s in order: `Sub-features`,
`How to get to it (user POV)`, `Driving it with verify-ios` (starting with `Preconditions:`), `Gotchas`.
Keep implementation details out; name user paths, stable handles, required state, steps and observable proof.

## Features

- [Address bar](./address-bar.md): typing a URL, loading it, reading the page, focus and keyboard (examples t2, t3, t9).
- [Tabs](./tabs.md): new tab, switch, close, tab count, both tab-switcher layouts (t4).
- [Link context menu](./link-context-menu.md): long-press a link, open in a new tab (t5).
- [Fire button](./fire-button.md): close tabs and clear data, with its pixels and wide event (t7).
- [Personal Information Removal](./pir.md): run a live broker scan and complete the opt-out for the selected record, with a pause for manual subscription setup.
- [Duck.ai](./duck-ai.md): open Duck.ai, send a prompt, read the answer; native input on iPhone, web input on iPad (t8).
- [Site permissions: location](./site-permissions-location.md): DuckDuckGo's permission sheet, then the iOS alert (t6).

Example ids refer to `examples/t<n>_*.py`.
