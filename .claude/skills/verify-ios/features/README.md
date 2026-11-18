# DuckDuckGo iOS verification map

The maintained source for verifying user-facing behavior of the DuckDuckGo iOS browser with `verify-ios`. Read this
index, then the feature file for what you are proving. Each feature lists every user entry point on iPhone and iPad;
a proof that drives one convenient entry point is incomplete when the file lists others that the change touches.
The map holds only features someone keeps current: add a file only when you will maintain it.

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
- Environment failures (see each file's Gotchas and SKILL.md's known environment issues) are reported as
  environment, not as product bugs.

## Feature entry contract

Each file: an H1, one paragraph of user-visible behavior, then exactly these H2s in order: `Sub-features`,
`How to get to it (user POV)`, `Driving it with verify-ios` (starting with `Preconditions:`), `Gotchas`.
Keep implementation details out; name user paths, stable handles, required state, steps and observable proof.

## Shared steps

`lib/verify_ios/steps.py` holds each quirk once, so every proof gets it right. The ids a step uses are in
`steps.IDS`, by device.

- `fresh_start`: reinstalls and launches the app, restores default capture conditions, then leaves the address bar. A
  fresh tab sometimes opens with the bar focused and sometimes not; the step always ends with it unfocused and the
  keyboard hidden. Without that, tapping the iPhone bar on the new-tab page fires no `m_addressbar_click_ntp_*` pixel.
- `dismiss_address_bar`: taps the dismiss control if it exists, and does nothing otherwise. The control differs by
  device: `UnifiedToggleInput.Button.Dismiss` (iPhone) and `Browser.OmniBar.Button.Dismiss` (iPad). A new tab opens
  with the bar focused, and on iPhone the keyboard then covers the toolbar, so its buttons are `NOT_HITTABLE` until you
  dismiss. An action's own `after.keyboard` can be stale while the keyboard animates out: prove hiding with
  `ios.expect_keyboard(shown=False)`.
- `open_url`: taps `searchEntry`, types the URL and submits, then waits until the tab's URL has changed and contains
  it. Opening the URL the tab already shows can't be told apart, so don't. Page text reaches the accessibility tree a
  moment after the URL changes, so pass `wait_for` before acting on it.
- `open_fixture`: `open_url` on the fixture page with a token, then waits for `label="token: <token>"`. On load the
  page writes its token to localStorage key `verify-ios`, and `#stored` shows what was there before: `empty` or
  `present`. Check the write happened before you prove a clear.
- `new_tab`: `cmd+t` on iPad. On iPhone it taps `Browser.Toolbar.Button.TabSwitcher`, then whichever control exists of
  `role=button label="New Tab"` and `label="Add 24"`: the tab switcher ships in two layouts that alternate between
  runs (`tap_first_present` probes both). The new tab opens with the bar focused.
- `tab_count`, `expect_tab_count`: the count is the numeric label right after `Browser.Toolbar.Button.TabSwitcher` in
  the native tree. Count tabs this way, not with `ios.handles()`, which skips new-tab pages until a page loads.
- `switch_to_tab`: iPad taps the tab in the tab bar; iPhone opens the switcher first. Both pick the fixture tab with
  `nth=0` (see Driving conventions).
- `close_current_new_tab`: iPad taps `Close tab` or `Close Tab` in the tab bar. iPhone opens the switcher, taps
  `Close Tab`, `Close tab` or `Close "New Tab"`, then Done (`TabSwitcher.Button.Done` or `role=button label="Done"`).
- `fire`: taps the Fire button (`Browser.Toolbar.Button.Fire` on iPhone; on iPad it has no id, only the icon label
  `Fire Solid 24`), screenshots the sheet, taps `alert.forget-data.confirm`, then waits for `searchEntry`: the app
  rebuilds the tab UI after clearing. "Closes all tabs" needs a second tab first. The remaining tab is a blank new-tab
  page, so `ios.url()` fails there by design; use `ios.expect_no_web_page()`. `m_forget-all-executed_daily_*` is a
  daily pixel: a second Fire in one run logs it `Skipped`, without the `_ios_<form factor>` suffix.
- `reset_location_permission`, `set_simulated_location`: simulator settings that a reinstall doesn't reset, so each
  registers its undo with `ios.on_cleanup`. The iOS location alert belongs to SpringBoard and has three buttons, so
  `ios.alert` needs `button=`.
- `open_duckai_new_chat`, `send_duckai_prompt`, `read_duckai_answer`: see [Duck.ai: full-tab chat](./duck-ai-tab.md).
- `duckai_chat_id`, `new_duckai_chat_tab`, `duckai_history`, `delete_current_duckai_chat`, `duckai_storage`: see
  [Duck.ai: full-tab chat](./duck-ai-tab.md). After any manual Fire, the app covers its window with an invisible
  overlay until clearing finishes, so every control reads as not hittable until then; wait for a control to be
  `visible` again rather than retrying taps.

## Features

- Duck.ai
  - [Full-tab chat](./duck-ai-tab.md): open Duck.ai, send a prompt, read the answer, chat history, attachments,
    deleting a chat; native input on iPhone, web input on iPad (examples t8, t12).
  - [Contextual chat](./duck-ai-contextual.md): Duck.ai in a sheet over a web page. Not mapped yet.

## Worked examples

`examples/t<n>_*.py` show how to drive the harness, not how to verify a feature: t1 launch and build identity, t2,
t3 and t9 the address bar, page reads and focus, t4 tabs, t5 a long-press menu, t6 a permission sheet and an iOS
alert, t7 the Fire button with pixels and a wide event, t10 capture conditions. `selftest` runs t7 on each device
because it needs no live service. t8 and t12 are Duck.ai proofs: t12 deletes a chat and reads history and storage
before and after.
