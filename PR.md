Task/Issue URL: https://app.asana.com/1/137249556945/task/1219231427593373

Base: `alex/cpm-messaging-readiness-telemetry`, `713d67419a` — the same telemetry base as #7379 and the standalone Network-process recovery fix.

### Description

Closing a browser window can stop Cookie Pop-up Management in a shared pinned tab that remains open elsewhere. Preserve surviving tabs when WebKit processes the window closure, while continuing to report tabs that genuinely close. This addresses the remaining macOS P5 case with `tab_in_context=false` after #6827.

The macOS flag `webExtensionSharedPinnedTabWindowClose` controls the fix and defaults to OFF. Remote rollout uses `webExtensions.sharedPinnedTabWindowClose` in `duckduckgo/privacy-configuration`. Each window reads the flag when closing starts; its closing-tab list then stays stable for the rest of that close transaction. Enabling the flag protects subsequent closes; it does not repair a tab WebKit already forgot.

### Testing Steps

#### Manual reproduction and acceptance

1. On macOS 15.4+, open the production worktree's `DuckDuckGo.xcworkspace` and run **macOS Browser**, **Debug**, **My Mac**. Enable internal user state if needed for **Debug → Feature Flag Overrides → Web Extensions**. Set these flags explicitly:

   | Flag | Reproduce failure | Verify fix |
   | --- | --- | --- |
   | `webExtensions` | ON | ON |
   | `embeddedExtension` | ON | ON |
   | `webExtensionStateRestorationGate` | ON | ON |
   | `cpmDiagnosticsRecorder` | ON | ON |
   | `cpmBackgroundDelegateProxy` | ON | ON |
   | `webExtensionSharedPinnedTabWindowClose` | **OFF** | **ON** |
   | `cpmMessagingHangRecovery` | OFF | OFF |
   | `cpmBackgroundGraveyardTreatment` | OFF | OFF |

2. Enable Cookie Pop-up Management in Settings and leave **Simulate CPM Breakage** off. In **Settings → General → Tabs**, select **Shared across all windows** for pinned tabs. Start with a healthy test setup after relaunching this test browser.
3. Open two regular browser windows, A and B, each with regular control tabs. In A, open [the autoconsent test page](https://privacy-test-pages.site/features/autoconsent/) and pin it. The same pinned tab must appear in both windows. Select a regular tab in A, then select the shared pinned tab in B. Confirm the test button becomes **I was clicked!** and its privacy dashboard reports **Cookies Managed**.
4. Close **window A** using its red window-close button, leaving B and the shared pinned tab open. Reload the pinned test page in B twice. With the fix **OFF**, expect the freshly loaded test button to remain unclicked and the fresh **Cookies Managed** result to be absent. Regular control tabs and a newly opened test-page tab should still work. The failure diagnostics identify the surviving tab as `tab_in_context=false`. Do not use Fire, reload the extension or relaunch while checking this failure.
5. Turn the fix **ON**, relaunch to establish another healthy setup, and repeat steps 2–4. Expect the pinned page to keep working on both reloads and regular/new-tab controls to stay healthy. Repeat by opening another window, selecting the shared pin there and closing the previous window; CPM must still work without extension reload.
6. With the fix ON, repeat after leaving the healthy test page idle until WebKit unloads its background (normally about 30 seconds; the app test waits for the actual unload). Close the other window, then reload the surviving pinned page twice. Both first and subsequent navigations must work.
7. Close the last regular window while shared pinned tabs exist, then open a new window without quitting the app. The shared pinned tab must return and CPM must still work.
8. Repeat with **Window → Merge All Windows**, and with moving a regular tab from A to B before closing A. The shared pinned tab and moved regular tab must keep working.
9. In a fresh setup with **Separate in each window**, pin the test page only in A, keep B open and close A. That per-window pinned tab must close with A; regular/new tabs in B must remain healthy.
10. Check runtime flag changes on windows that are already open: create the healthy shared-pin setup with the fix OFF, enable it **before closing A**, then close A and verify the pin works in B. Repeat from a healthy setup with the fix initially ON but disabled before closing A; expect the original failure. A close already in progress keeps the mode it started with.
11. Restore the flag overrides and pinned-tab preference changed for this test. The new fix flag remains OFF by default; this PR does not change remote configuration.

#### Automated reproduction and regression checks

The production branch is `alex/cpm-p5-pinned-window-close`. The app fixture, dedicated schemes and DEBUG hooks live only in local review branch `codex/cpm-p5-integration-tests`, worktree `alex/cpm-p5-integration-tests`. The review-only delta must not be merged into main.

1. In the production worktree, run the shared tests:
   ```sh
   swift test --package-path SharedPackages/WebExtensions --skip-update
   ```
2. Test **macOS Unit Tests**, selecting `WindowsManagerPopupTests`, `PinnedTabsManagerTests`, `TabCollectionViewModelTests` and `TabWebExtensionTabTests`. Expect **210 passed**, including eight new window-close regressions for real `WKWebExtensionWindow` enumeration, active tabs, empty close lists and runtime flag changes.
3. Open the review worktree's workspace and test **CPM Integration Tests** on **My Mac**. Expect **8 passed, 0 failed, 0 skipped**: repeated shared-pin closes, real background idle, last-window reopening, merge, move, diagnostics OFF, separate-pin controls and runtime enable.
4. Test **CPM Integration Tests - Fixes Disabled**. It disables the actual production flag and selects five affected close scenarios plus the merge control. Expect **5 functional failures, 1 passed, 0 skipped**: the close scenarios lose a surviving shared pinned tab, while the tested merge path stays healthy in both flag states. A build/setup error, crashed host or skipped test is not a valid negative control.
5. Test **CPM Integration Tests** again. Require all eight to pass again. For the final verification, run all eight three times using `test-without-building` and `-test-iterations 3`: **24 successful executions**. Use the same app/XCTest binaries throughout ON → OFF → ON; only the fixture's flag state changes. Full CLI instructions and scenario details are in `macOS/IntegrationTests/CPM/README.md` on the review branch.
6. Run macOS unit and app test hosts sequentially: the existing `TestRunHelper` uses a shared temporary root. Concurrent hosts can remove each other's test databases. The app fixture isolates its extension resources separately.

Local validation on macOS 26.7.1 / Xcode 27.1:

- Telemetry-base regression: **1 functional failure, 0 skips**, caused by real WebKit registration loss after a real window close.
- Shared WebExtensions package: **758 passed, 0 failed**, in each of two complete runs.
- Selected macOS unit tests: **210 passed, 0 failed, 0 skipped**, repeated twice (**420 successful executions**); eight new close-contract/runtime-flag regressions.
- Same app/XCTest binaries: **ON 8 passed → OFF 5 expected functional failures + 1 healthy merge control → ON 24/24 executions passed** (all eight methods repeated three times), with no skips. All **4,717 bundle files** were byte-identical throughout the cycle.
- Separate production macOS and full iOS Simulator app builds passed. The production macOS app passed deep/strict code-signature verification.
- Strict SwiftLint passed across all six production and eight review-only Swift files. Bundled ZIPs, dependency pins and telemetry definitions are unchanged.

### Impact

Medium: changes the tabs exposed to WebKit during a macOS window close, for every loaded Web Extension context when enabled. Open-window enumeration and genuine tab closure retain their existing behavior.

#### What could go wrong?

- A surviving shared or moved tab could be forgotten again → snapshot only genuinely closing tabs before sending close notifications; app regressions cover shared pins, repeated/last closes, merge and moves.
- A genuinely closed tab could remain registered → retain the existing ownership filter and verify regular-tab removal plus the separate-pinned-tab control.
- A runtime flag change could expose inconsistent lists during one close → latch the list at the start of the close transaction; unit tests cover disable/enable and repeated queries.

### Quality Considerations

This fixes the remaining `didCloseWindow` path: filtering our explicit `didCloseTab` calls alone was insufficient because WebKit queries the closing window's tabs itself. The snapshot also prevents a surviving tab from being reported as active in that closed window. No retained tab is removed from its app model or re-registered, and the extension context is preserved.

The production fix uses the public window/tab delegate contract and adds no process termination, telemetry or extension-bundle change. The shared controller-configuration injection keeps its existing default and permits isolated test stores, as in #7379 and the Network-process fixture. The app regressions execute real pinning, window close, move/merge callbacks, native dashboard delivery and actual content-script `initResp`; they do not call synthetic close events or disable DEBUG lifetime guards. Negative controls check WebKit registration loss immediately, before a missing-reply timeout.

This addresses the reproduced macOS P5/tab-registration case. Natural listener loss with a correctly registered tab, P6 controller replacement, iOS lifecycle failures, background readiness and Network-process recovery remain separate work. Local validation is not an external review or CI run.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
