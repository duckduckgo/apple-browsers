# Tabs

The user opens a new tab, switches between tabs, and closes one; the tab count and the visible page follow. iPhone
does this through the tab switcher; iPad also has a tab bar and `cmd+t`.

## Sub-features

- `tabs-new` opens a new tab (count +1, bar focused).
- `tabs-switch` returns to an existing tab and shows its page.
- `tabs-close` closes a tab (count −1); the remaining tab keeps its page.
- `tabs-count` the count shown on the tab-switcher button.

## How to get to it (user POV)

- iPhone: toolbar tab-switcher button → new tab / tap a tab / close a tab → Done.
- iPad: `cmd+t` for a new tab; tap a tab in the tab bar to switch; the tab bar's close button; or the tab switcher.

## Driving it with verify-ios

Preconditions:

- `steps.fresh_start(ios)`, then `steps.open_fixture(ios, token)`: one tab showing `verify-ios fixture`. Count 1.

- **Read the count.** `steps.tab_count(ios)`: the numeric label right after `Browser.Toolbar.Button.TabSwitcher` in
  the native tree. Assert with `steps.expect_tab_count(ios, n)`.
- **New tab.** `steps.new_tab(ios)`: iPad presses `cmd+t`; iPhone taps `Browser.Toolbar.Button.TabSwitcher`, then
  whichever exists of `role=button label="New Tab"` / `label="Add 24"`. Proof: count reads 2.
- **Leave the focused bar.** The new tab opens with the bar focused and (iPhone) the keyboard over the toolbar:
  `steps.dismiss_address_bar(ios)` first.
- **Switch back.** `steps.switch_to_tab(ios)` taps `label="Open \"verify-ios fixture\" at 127.0.0.1" nth=0` (iPad: in
  the tab bar; iPhone: after opening the switcher). Proof: `ios.expect_url_contains(token)`.
- **Close the new tab.** `steps.close_current_new_tab(ios)`: iPad taps `Close tab` / `Close Tab` in the tab bar;
  iPhone opens the switcher, taps `Close Tab` / `Close tab` / `Close "New Tab"`, then Done
  (`id=TabSwitcher.Button.Done` or `role=button label="Done"`). Proof: count reads 1 **and**
  `ios.expect_web_text("#token", token)`.
- Worked proof: `examples/t4_tabs.py`.

## Gotchas

- The tab switcher ships in **two layouts** that alternate between runs: (`New Tab` + `Done` text buttons) or
  (`Add 24` + `TabSwitcher.Button.Done`). `steps.tap_first_present` probes both; never assume one.
- A new tab opens with the address bar focused; on iPhone the keyboard covers the toolbar, so its buttons are
  `NOT_HITTABLE` until you dismiss.
- The iPad tab bar and switcher expose the same tab label twice; one is covered. Use `nth=0` after checking `find`.
- `ios.handles()` ignores new-tab pages (no handle until a page loads); count tabs from the native tree.
