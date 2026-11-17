# Site permissions: location

A page asks for the user's location. DuckDuckGo shows its own permission sheet first; if the user allows, iOS then
shows its system location alert. The page receives the position or a denial.

## Sub-features

- `geo-sheet` DuckDuckGo's site-permission sheet appears when a page requests location.
- `geo-allow` Allow (once) → iOS alert → the page gets a position.
- `geo-deny` Never Allow → the page gets a permission denial, and no iOS alert appears.

## How to get to it (user POV)

- Any page that calls `navigator.geolocation.getCurrentPosition`, iPhone or iPad.

## Driving it with verify-ios

Preconditions:

- `steps.reset_location_permission(ios)` (forgets the iOS grant) and `steps.set_simulated_location(ios, 52.52, 13.405)`.
  Both are simulator settings that a reinstall doesn't reset, so both register their undo with `ios.on_cleanup`.
- `steps.fresh_start(ios)` (reinstall also clears DuckDuckGo's per-site permission), then `steps.open_fixture`.

- **Request.** `ios.tap('role=button label="ask for location"')`; proof: `ios.expect_web_text("#geo-result", "asking")`.
- **DuckDuckGo sheet.** `ios.expect_visible("id=SitePermissions.Dialog", 6)`; take `ios.shot`.
- **Deny.** `ios.tap("id=SitePermissions.Dialog.NeverAllow")`; proof: `ios.expect_web_text("#geo-result", "denied", 16)`.
- **Allow.** `ios.tap("id=SitePermissions.Dialog.AllowOnce")`, then the iOS alert:
  `ios.alert("accept", button="Allow While Using App", timeout=6)` (this alert has three buttons, so `button=` is
  required; "accept" alone is refused as ambiguous); proof: `#geo-result` becomes `granted`.
- **Deny shows no iOS alert.** After Never Allow, `ios.expect_no_alert(within=3)`.
- Worked proof (deny): `examples/t6_location_deny.py`.

## Gotchas

- **Known environment issue:** the iOS 27.0 simulator may never deliver a location fix. After both prompts were
  answered, the page reports `error` (geolocation error 3, timeout) instead of `granted`. Record the allow path with
  `ios.unverified(...)` as environment, not as a product bug. The sheet, the alert and the deny path still prove the
  permission flow.
- The iOS alert belongs to SpringBoard, not the app; `ios.alert` searches both.
- Permission state survives relaunches; reset both the iOS grant and the app (reinstall) between runs.
