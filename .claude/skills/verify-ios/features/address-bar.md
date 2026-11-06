# Address bar

The user taps the address bar, types a URL or search, submits, and the page loads in the current tab. Tapping the
bar focuses it and shows the keyboard; dismissing returns to the page. On iPad, `cmd+l` on a hardware keyboard
focuses the bar.

## Sub-features

- `omnibar-load` types a URL and submits; the tab loads it.
- `omnibar-read` the loaded page's content is readable from the native tree and from the web channel.
- `omnibar-focus` tap focuses the bar and shows the keyboard; dismiss hides both.
- `omnibar-cmd-l` (iPad) `cmd+l` focuses the bar.

## How to get to it (user POV)

- Tap the address bar (`searchEntry`) on any tab, iPhone or iPad.
- A new tab opens with the bar already focused (see [Tabs](./tabs.md)).
- iPad: press `cmd+l` with a hardware keyboard.

## Driving it with verify-ios

Preconditions:

- `steps.fresh_start(ios)`; a fresh `token = ios.token(...)`.

- **Focus.** `ios.tap("id=searchEntry")`, then `ios.expect_keyboard(shown=True)` and `ios.expect_focused("searchEntry")`.
- **Load.** `ios.type("id=searchEntry", ios.fixture_url(token), submit=True)` (or `steps.open_url` / `steps.open_fixture`).
  Proof: `ios.expect_url_contains(token)` **and** `ios.expect_web_text("#token", token)`.
- **Pixels.** After `steps.fresh_start` (bar not focused) and `ios.mark()`, tapping the bar on the new-tab page fires
  `m_addressbar_click_ntp_ios_<form factor>`. iPhone also fires
  `m_aichat_experimental_omnibar_keyboard_go_pressed_ios_phone` (`mode: search`) on submit.
- **Read natively.** `ios.expect_visible(f'label="token: {token}"')`: web text reaches the accessibility tree a moment
  after the URL changes, so wait; never act early.
- **Dismiss.** `ios.tap(steps.ids(ios)["dismiss"])`, then `ios.expect_keyboard(shown=False)` and
  `ios.expect_not_focused("searchEntry")`.
- **cmd+l (iPad).** `ios.key("cmd+l")`, then `ios.expect_focused("searchEntry")`.
- Worked proofs: `examples/t2_address_bar.py`, `t3_read_page.py`, `t9_keyboard_focus.py`.

## Gotchas

- The dismiss control differs by device: `UnifiedToggleInput.Button.Dismiss` (iPhone) vs
  `Browser.OmniBar.Button.Dismiss` (iPad). Use `steps.ids(ios)["dismiss"]` or `steps.dismiss_address_bar`.
- An action's own `after.keyboard` can be stale while the keyboard animates out; prove hiding with
  `ios.expect_keyboard(shown=False)`.
- `ios.navigate` fails on the new-tab page; use the address bar for the first load.
- Typing with nothing focused fails with `NOT_FOCUSED`: the driver refusing, not the app misbehaving.
- After a fresh start the iPhone bar is sometimes already focused; tapping it then doesn't fire
  `m_addressbar_click_ntp_ios_phone`. Don't assert that pixel on iPhone without first leaving the bar.
