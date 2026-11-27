# Shared steps

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

Duck.ai contextual chat (details in [Duck.ai: contextual chat](./duck-ai-contextual.md)):

- `CONTEXTUAL_FLAGS`: the flags a contextual proof pins; `contextualDuckAIMode` is off by default.
- `open_contextual_chat`, `attached_context`: entry button, then Ask About Page; the attached page's title or `None`.
- `send_contextual_prompt`, `read_contextual_answer`: the input is `role=textview id=searchEntry` (the address bar
  shares the id). The answer is read from the native tree, because the web channel reads the tab, not the sheet.
- `fire_contextual_chat`, `expand_contextual_chat`: the controls differ by device (`CONTEXTUAL_IDS`).

Sync & Backup (details in [Sync & Backup](./sync.md)):

- `SYNC_FLAGS`: the `FLAGS` a sync proof pins: the setup UI (`syncImprovedPairingFlow`) and the V2 pairing protocol
  (`syncCanUseV2ConnectFlow`, `syncCanShowV2ConnectCode`), all on.
- `SYNC_DEV_PROFILE`: the `PROFILE` a sync proof sets, `{"debug.syncEnvironment": "Development"}`. Debug builds talk
  to the production sync server otherwise.
- `open_settings`, `open_sync_settings`: the browsing menu (`Browser.Toolbar.Button.Menu` on iPhone,
  `Browser.OmniBar.Button.BrowsingMenu` on iPad), Settings, then the row whose label carries the state
  (`Sync & Backup, Off` or `, On`).
- `unlock_device`: answers the system passcode sheet ("Unlock device to set up Sync & Backup") when it appears. It
  belongs to SpringBoard, so it types into `app=springboard id="Passcode field"` and taps `app=springboard id=Done`;
  typing `0000\n` in one go reports no effect. One unlock stays valid for a while, so the next gated step may not ask:
  the step returns whether it did.
- `copy_in_app`: puts text on the clipboard through Settings > All debug options > Sync > "Paste and Copy Recovery
  Code". Paste Sync Code doesn't see text written from the host with `simctl pbcopy`. Starts from the browser, ends
  on the Settings list.
- `clipboard`: reads the simulator's clipboard from the host (read-back only).
- `turn_off_and_delete_server_data`: Turn Off Sync & Backup with "Also delete server data?" on (it starts off when more
  than one device is synced), then Permanently Delete.
- `close_settings`, `recover_with_code`, `allow_camera`, `answer_alert`: back to the browser; recover from the browser
  with a code (True on "Sync & Backup enabled", False on "Sync failed."); allow the camera prompt each time it shows
  (it can show twice in a row); press an alert button, waiting when the runner reports the alert still up.
