# Fire button

The user presses the Fire button and confirms; all tabs close and browsing data (cookies, localStorage) is cleared,
leaving one blank tab.

## Sub-features

- `fire-sheet` the Fire button opens the confirmation sheet.
- `fire-clear` confirming closes all tabs and leaves one blank tab.
- `fire-data` site data is gone: a page that wrote localStorage finds it empty on the next load.
- `fire-telemetry` the clear is reported by pixels and a `data-clearing` wide event.

## How to get to it (user POV)

- iPhone: the Fire button in the bottom toolbar.
- iPad: the Fire button in the top bar.

## Driving it with verify-ios

Preconditions:

- `steps.fresh_start(ios)`, then `steps.open_fixture(ios, token)` (the fixture writes localStorage on load;
  `#stored` reads `empty` on the first load). Check the write happened
  (`ios.eval("return {v: localStorage.getItem('verify-ios')}")` is the token), or "cleared" proves nothing.
- A second tab (`steps.new_tab`, count 2), then `steps.dismiss_address_bar` and `ios.mark()` right before Fire.

- **Press and confirm.** `steps.fire(ios)`: taps the Fire button (`id=Browser.Toolbar.Button.Fire` on iPhone,
  `label="Fire Solid 24"` on iPad), screenshots the sheet, taps `id=alert.forget-data.confirm`, waits for `searchEntry`.
- **Tabs closed.** `steps.expect_tab_count(ios, 1, 10)` (from 2) and `ios.expect_no_web_page()` (the remaining tab
  is a blank new-tab page; `ios.url()` would fail there, by design).
- **Data cleared.** `steps.open_fixture(ios, ios.token(...))` again, then `ios.expect_web_text("#stored", "empty")`
  (`present` would mean localStorage survived).
- **Telemetry.** `ios.expect_pixel(f"m_forget-all-executed_daily_ios_{ios.form_factor}")` and
  `ios.expect_wide_event("data-clearing", status="SUCCESS")`. Other pixels the same press fires:
  `mf_bp_ios_<ff>`, `mf_ios_<ff>`, `mf_dc_ios_<ff>`, `m_forget-all-pressed_browsing_daily_ios_<ff>`.
- Worked proof: `examples/t7_fire_button.py`.

## Gotchas

- The **iPad Fire button has no accessibility id**; its label is the icon name `Fire Solid 24`.
- The URL check alone does not prove data was cleared; the `#stored` reload check does.
- After clearing, the app rebuilds the tab UI; wait for `searchEntry` before the next action (`steps.fire` does).
- `m_forget-all-executed_daily_*` is a daily pixel: a second Fire in the same run logs it `Skipped`, under the name
  without the platform suffix (`m_forget-all-executed_daily`). `fresh_start` clears that state.
- "Closes all tabs" needs more than one tab: open a second one first (the worked proof goes 2 → 1).
