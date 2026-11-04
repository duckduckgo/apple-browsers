# Link context menu

The user long-presses a link on a page; a menu appears with actions such as Open in New Tab; choosing it opens the
link's target in a new tab.

## Sub-features

- `link-menu-show` long-press on a link shows the context menu.
- `link-open-new-tab` Open in New Tab creates a tab showing the link target.

## How to get to it (user POV)

- Long-press any link in a web page, iPhone or iPad.

## Driving it with verify-ios

Preconditions:

- `steps.fresh_start(ios)`, then `steps.open_fixture(ios, token)`; record `before = len(ios.handles())`.

- **Find the link.** `ios.wait('role=link label="external link"', "visible", 8)` (web links appear in the native tree).
- **Long-press.** `ios.long_press('role=link label="external link"', ms=1000)`. Proof:
  `ios.expect_visible('label="Open in New Tab"')`; take `ios.shot("menu")`.
- **Open in new tab.** `ios.tap('label="Open in New Tab"')`. Proof: `len(ios.handles()) == before + 1` **and** the
  URL ends with `/target.html` (both via `ios.eventually`).
- Worked proof: `examples/t5_link_menu.py`.

## Gotchas

- Context-menu animations never report idle to XCTest; the runner skips that wait (private swizzle). If long-presses
  start taking ~60 s, that swizzle stopped working on this Xcode.
- Act on the link through the native tree; `web:*` locators are read-only.
