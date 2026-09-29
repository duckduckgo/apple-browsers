# Per-site permission manager — UI test scenarios (XCUITest)

A deliberately small suite: six core scenarios that catch the failures that would hurt users or block a release, plus three optional ones. Everything else stays in unit tests (`SitePermissions` package) and the manual [test-scenarios.md](test-scenarios.md).

**Purpose and scope:** these are XCUITests for **local validation of changes** — run them from Xcode or via XcodeBuildMCP before opening or updating a PR. They are **not wired into CI** for now, by decision. The iOS project is migrating from Maestro to XCUITest, so the existing XCUITests are the pattern to follow; do not write Maestro flows for these scenarios.

## Read first: where the tests live and how to run them

- Put the tests in the existing XCUITest bundle `iOS/AtbUITests`, in a new `SitePermissionsXCUITests.swift`. Copy the setup pattern from `FloatingUIXCUITests.swift` in the same bundle: launch arguments, the in-test local `HttpServer` that serves fixture pages, and the `waitForHittable` helpers. ("Atb" is the bundle's historical name from the ATB install-statistics integration tests it started with; it is now the catch-all XCUITest target for the browser.)
- Run locally against an iOS Simulator with the `iOS Browser` scheme, selecting only the new test class (`-only-testing:AtbUITests/SitePermissionsXCUITests`). Do not add CI wiring.
- **Launch setup** (from `LaunchOptionsHandler`): `-clearAllDefaults`, `isRunningUITests` (or env `UITEST_MODE=1`), `-isOnboardingCompleted true`, `-isInternalUser true`, and the flag override `-ff.sitePermissions true` (or `false` for the flag-off scenario). Flag overrides only apply with internal-user mode on.
- **Controlling the iOS system permission** (deterministic, no manual step): `XCUIApplication.resetAuthorizationStatus(for: .camera / .microphone / .location)` resets to not-determined before a test; answer the system alert through `XCUIApplication(bundleIdentifier: "com.apple.springboard")` (tap "Allow" / "Don't Allow"); to start a test in the "already denied" state, deny the alert once in the test's own setup. `xcrun simctl privacy <udid> revoke camera <bundle>` works as a pre-step outside the test process.
- **Fixture pages:** the existing FloatingUI tests serve HTML from an in-test local server — do the same with tiny pages that call `getUserMedia({video:true})`, `getUserMedia({audio:true})`, and `navigator.geolocation.getCurrentPosition`, writing the outcome into a DOM element the test can read. This keeps the suite offline and stable. Two hostnames (for the subdomain scenario) can be simulated with `127.0.0.1` vs `localhost`, or by adding `/etc/hosts` entries on the local machine — otherwise use the public `privacy-test-pages.site` test subdomains.
- **Identifiers already on the stack** (branch 6): dialog `SitePermissions.Dialog`, `.Dialog.Title`, `.Dialog.Body`, `.Dialog.AllowOnce`, `.Dialog.AllowWhileUsingSite`, `.Dialog.NeverAllow`; reminder `SitePermissions.Reminder`, `.Reminder.Title`, `.Reminder.ChangePermissions`, `.Reminder.HideVoiceSearch`, `.Reminder.Cancel`; sheet `SitePermissions.Sheet`, `.Sheet.Title`, `.Sheet.Close`, `.Sheet.Camera`, `.Sheet.Microphone`, `.Sheet.Geolocation`, `.Sheet.ReloadCaption`, `.Sheet.Actions`, `.Sheet.Reminder`; Settings `Settings.SitePermissions.Global.<camera|microphone|geolocation>`, `Settings.SitePermissions.Site.<host>`, `Settings.SitePermissions.RemoveAll`, `Settings.SitePermissions.RemoveSite`, per-site rows `Settings.SitePermissions.Site.<type>`.
- **Identifiers still missing — add them in the first PR of this suite:** the browser-menu row (currently only the label "Site Permissions"), the two sheet action buttons inside `Sheet.Actions` (Remove Permissions, Go to System Settings), the Main Settings entry row, and the toast/Undo button.

## Core scenarios (must have)

### 1. Flag off keeps today's behavior
Why: this protects every release until rollout completes; it's the single most valuable test.
- Launch with `-ff.sitePermissions false`. Camera permission not determined.
- Load the camera fixture; trigger `getUserMedia`.
- Assert: WebKit's own prompt appears (a system-style alert containing the site name and "Camera"), and **no** `SitePermissions.Dialog` exists. Open the browser menu: no "Site Permissions" row. Open Settings: no Site Permissions entry.

### 2. First camera request: our dialog first, then the system prompt, then it works
Why: the core product change (site-first ordering) and the happy path.
- Flag on. `resetAuthorizationStatus(for: .camera)`.
- Trigger `getUserMedia`. Assert `SitePermissions.Dialog` appears with all three buttons and **no** system alert yet.
- Tap `SitePermissions.Dialog.AllowWhileUsingSite`. Assert the iOS system alert appears now; tap "Allow" via springboard.
- Assert the page reports success. Open the menu: the "Site Permissions" row exists; tap it: `SitePermissions.Sheet.Camera` shows the allowed state. Open Settings > Site Permissions: `Settings.SitePermissions.Site.<host>` exists.
- Reload and trigger again: no dialog, no system alert, page reports success.

### 3. Never Allow is remembered and denies silently; the sheet can undo it
Why: the persistent-deny path plus the recovery-from-own-decision loop that motivated the project.
- Flag on. Trigger `getUserMedia`; tap `SitePermissions.Dialog.NeverAllow`. Assert the page reports a permission error.
- Reload; trigger again. Assert **no** dialog and the page reports an error.
- Open menu > Site Permissions; on `SitePermissions.Sheet.Camera` change to Ask Each Time. Assert `SitePermissions.Sheet.ReloadCaption` is shown.
- Close, reload, trigger again. Assert the dialog appears again.

### 4. Allow Once is page-scoped and never listed
Why: the privacy rule (no passive records) and the lifetime decision.
- Flag on, camera already authorized at the OS level (grant it in setup).
- Trigger; tap `SitePermissions.Dialog.AllowOnce`. Assert the page reports success and no system alert.
- Trigger again on the same page. Assert no new dialog (still granted).
- Reload; trigger. Assert the dialog appears again.
- Open Settings > Site Permissions. Assert no `Settings.SitePermissions.Site.<host>` for this host.

### 5. Recovery when the OS permission is already denied
Why: the reminder dialog is the fix for the top user complaint, and it's the flow most likely to regress.
- Flag on. In setup, put the camera in the denied state (trigger once, tap "Don't Allow" on the system alert; or `simctl privacy revoke`).
- Trigger `getUserMedia`; tap `SitePermissions.Dialog.AllowWhileUsingSite`.
- Assert **no** system alert, `SitePermissions.Reminder` appears with `.Reminder.ChangePermissions` and `.Reminder.Cancel`, and the page reports a permission error. Tap Cancel.
- Open menu > Site Permissions. Assert `SitePermissions.Sheet.Reminder` is present (the Go to System Settings state) and the site's Allow was kept (the camera row shows Always Allow, not Never Allow).
- Do **not** tap Change Permissions in the automated test (it leaves the app); assert its existence only.

### 6. Fire Button clears permissions except fireproofed sites, and keeps global defaults
Why: exercises PR 1's worker end-to-end and the fireproofing rule that surprised reviewers.
- Flag on. Save Allow While Using Site on host A and host B (two fixture hosts). Fireproof host A via the menu. Set the global Camera default to Never Allow in Settings.
- Press the Fire Button and confirm.
- Open Settings > Site Permissions. Assert `Settings.SitePermissions.Site.<hostA>` exists and `...<hostB>` does not. Assert `Settings.SitePermissions.Global.camera` still shows Never Allow.

## Optional scenarios (add if time allows)

### 7. Decisions are per subdomain
- Save Never Allow on `a.<domain>`; visit `b.<domain>` and trigger. Assert the dialog appears (own record). Assert two separate rows in Settings. Requires two hostnames (see fixtures note).

### 8. Global Never Allow blocks new sites but not an already-allowed site
- Save Allow While Using Site on host A. Set global Camera to Never Allow. On host B: trigger, assert no dialog and an error. On host A: trigger, assert success without a dialog.

### 9. Geolocation goes through our dialog, not WebKit's
- Flag on, simulator location set (`XCUIDevice`/scheme location). Load the geolocation fixture; trigger `getCurrentPosition`. Assert `SitePermissions.Dialog` appears and WebKit's location alert does not. Allow; assert the page receives coordinates. Reload; assert Allow Once semantics as in scenario 4 (if Allow Once was chosen) or no re-prompt (if Allow While Using Site).

## Implementation notes for the agent

- One test class, `SitePermissionsXCUITests`, in `iOS/AtbUITests`, mirroring `FloatingUIXCUITests` for launch and the local fixture server. Add a `launchApp(flagEnabled:)` helper. Local-only for now: no scheme test-plan or workflow changes.
- Reset OS permissions in `setUp` for every test that touches the system prompt; tests must not depend on execution order.
- Handle the system alert through springboard with an explicit wait; add an interruption monitor as a fallback only.
- Prefer identifiers over labels; where an identifier is missing (menu row, sheet action buttons, Settings entry, toast), add it in the package/app first and reference it — never match on localized copy that is still under copy review.
- Keep the suite under ten tests. If a scenario needs more than one page reload and two prompts, it belongs in the manual doc, not here.
