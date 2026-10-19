# Embedded install, upgrade and P1/P2 wake regressions

**Review-only branch:** `codex/cpm-fix-init-loss-integration-tests` is based on `alex/cpm-fix-init-loss` and adds only this app test harness. This branch will not be merged into main; the production fixes and shared unit regressions are reviewed in [PR #7379](https://github.com/duckduckgo/apple-browsers/pull/7379).

To run the app regressions:

1. From the repository root, fetch and check out this branch:
   ```sh
   git fetch origin
   git switch --detach origin/codex/cpm-fix-init-loss-integration-tests
   ```
2. On macOS 15.4 or later, open `DuckDuckGo.xcworkspace` in Xcode.
3. Select **CPM Integration Tests** and **My Mac**.
4. Choose **Product → Test** (⌘U). Expect **8 passed, 0 failed, 0 skipped**. The scheme sets the opt-in and test flags automatically; leave the negative-control overrides unset.
5. Select **CPM Integration Tests - Fixes Disabled** and choose **Product → Test**. Expect exactly **6 failed, 0 passed, 0 skipped**. This scheme selects the six recovery tests and disables their production fix flags automatically; the expected failures are listed below.
6. Select **CPM Integration Tests** again and choose **Product → Test**. All **8 tests must pass** again.
7. Return to the production PR when finished:
   ```sh
   git switch --detach origin/alex/cpm-fix-init-loss
   ```

Run the **CPM Integration Tests** scheme on macOS 15.4 or later. It builds and signs the normal DuckDuckGo app and runs eight app-hosted XCTest methods, without the UI scheme's profile-cleaning preactions:

- `testSlowBackgroundWakeKeepsFirstNavigationHealthy`: after real WebKit idle unloading, an 8-second worker startup still delivers the first document's native dashboard and content-script `initResp`, without an initialization timeout or stuck event. The navigation gate waits at most 5 seconds.
- `testBackgroundLoadFailureRecoversOriginalDocument`: suspend only the test extension's background process for 45 seconds, observe WebKit's actual background-load error 6, resume it, and require automatic delivery to the original failed document. The context stays identical; subsequent navigation, a new tab and a new window must work.
- `testInstallDuringSessionInitIsDelivered`: port of #7379's install case. Enable the embedded extension during the session and immediately navigate an existing tab while its first worker startup is delayed by 4.5 seconds; require native dashboard and page `initResp`.
- `testUpgradeDuringSessionInitIsDelivered`: port of #7379's upgrade case. Mark the in-memory installation version outdated, upgrade through the real lifecycle coordinator, and navigate while the replacement's worker starts with a 4.5-second delay. Require the new identifier, recorded coexistence of the old and replacement contexts, native dashboard and page `initResp`.

- `testOverBudgetInstallRecoversFirstDocumentWithoutExtendingNavigationWait` and `testOverBudgetUpgradeRecoversFirstDocumentWithoutExtendingNavigationWait`: an 8-second startup outlives the unchanged 5-second gate. Require the first local document to finish within 6.5 seconds, before its dashboard response; then require exactly one automatic reload, unchanged URL/context, native dashboard, page `initResp` and both reload/response instrumentation stages.
- `testLateStartupDoesNotReloadEditedDocument`: change a field in the first document while the worker is still starting. Require no automatic reload or recovery pixel, and a healthy subsequent manual navigation.
- `testRecoveryPixelsUseSeparateNamesAndDailyCountFrequency`: use `PixelKitMock` to verify all five macOS names, prefixes, parameters and frequency through the production adapter.

The seven WebKit scenarios use real AppDelegate lifecycle callbacks, windows, tabs, native handlers and system WebKit. The extension ZIP is unchanged. An extracted test copy delays worker startup and records actual `initResp` delivery; it does not fabricate messages or drop callbacks. Temporary extension files, nonpersistent WebKit stores and a loopback HTTP server isolate the fixture. External extension pixel delivery is intercepted; native health events are attached as JSON. Any stopped process is resumed during cleanup. The host must have no existing windows or pinned tabs.

The **CPM Integration Tests - Fixes Disabled** scheme sets `CPM_APP_INTEGRATION_DISABLE_P1_P2_FIXES=1` and `CPM_APP_INTEGRATION_DISABLE_LATE_RECOVERY=1`. These fixture overrides switch the actual production feature flags, without changing the app binary or remote configuration. No environment editing or manual test selection is needed. The edited-document veto and pixel-adapter tests are omitted from this scheme because disabling recovery should not make them fail.

| Test selected by the disabled-fixes scheme | Production flag disabled | Expected failure |
|---|---|---|
| `testInstallDuringSessionInitIsDelivered` | `webExtensions.stateRestorationGate` | First document misses native dashboard/page `initResp` |
| `testUpgradeDuringSessionInitIsDelivered` | `webExtensions.stateRestorationGate` | First replacement-context document misses its response |
| `testSlowBackgroundWakeKeepsFirstNavigationHealthy` | `webExtensions.stateRestorationGate` | First navigation records a CPM response timeout |
| `testBackgroundLoadFailureRecoversOriginalDocument` | `webExtensions.cpmMessagingHangRecovery` | Times out waiting for same-document recovery after real WebKit error 6 |
| `testOverBudgetInstallRecoversFirstDocumentWithoutExtendingNavigationWait` | `webExtensions.cpmLateBackgroundDocumentRecovery` | Times out waiting for automatic first-document recovery |
| `testOverBudgetUpgradeRecoversFirstDocumentWithoutExtendingNavigationWait` | `webExtensions.cpmLateBackgroundDocumentRecovery` | Times out waiting for automatic first-document recovery |

Late document recovery is also disabled in the first four controls so that it cannot mask a disabled earlier fix. The two over-budget controls retain the 5-second navigation gate and isolate the late-recovery flag. A crashed host, skipped test or fixture-setup failure is not the expected result.

Eight additional methods in `WebExtensionLifecycleCoordinatorTests` validate navigation wake waiting, its timeout with a non-cancellable WebKit callback, cancellation, the disabled flag, a shared deadline for the same startup, a fresh deadline for a new startup, releasing pending navigations on lifecycle cancellation, and sharing the launch timeout with later navigations for the same startup. The shared-deadline regression covers waiters prepared both before and after the timeout while the background callback is still pending. Five additional `WebExtensionManagerTests` check replacement selection during coexistence/removal, diagnostics-disabled background-to-foreground retry, the runtime kill switch, and ignoring a superseded context. The iOS factory supplies `UIApplication` state independently of the diagnostics flag. Run these suites and the existing related diagnostics/monitor checks with:

```sh
cd SharedPackages/WebExtensions
swift test --filter 'WebExtensionManagerTests|WebExtensionLifecycleCoordinatorTests|CPMBackgroundLoadDiagnosticsTests|CPMMessagingHealthMonitorTests|CPMBackgroundReadinessRecoveryTests'
```

The previous 22-method research suite remains in the original investigation worktree. The eight app methods and their app hooks live only on this branch; the twenty-six new shared unit regressions remain in the production PR and are inherited here. These injected macOS timing/process conditions validate the fixes; they do not establish the natural trigger in every production session or reproduce real iOS suspension/resume.

The install/upgrade delay can be overridden with `CPM_APP_INTEGRATION_INSTALL_DELAY_MS`. A value of `5000` deliberately crosses the 5-second gate budget once WebKit startup overhead is included: measured callbacks arrived after 5.15–5.18 seconds, and upgrade sometimes lost its first document's response. The checkpoint commit `dff29dfb1e` documents this failure. The new opt-in document recovery targets it after gate release; increasing this value still does not extend the production timeout. The default 4500 ms leaves startup headroom while preserving the strict first-document assertions. Timeout/cancellation unit tests separately require releasing navigation when readiness never completes.

The independent remote flag `webExtensions.cpmLateBackgroundDocumentRecovery` defaults to **disabled** on both platforms; this harness explicitly enables it unless the negative-control variable is set. Recovery requires a document committed during a known unfinished startup, a real missing-response timeout, and a successful public WebKit background callback. It attempts at most one GET reload per document/startup within 30 seconds of startup. Changed/loading/closed/failed documents, edits/contenteditable, extension replacement, application background state and runtime flag disable veto it. The original five-second navigation bound and existing P1/P2 flags remain unchanged. Recovery does not depend on diagnostics being enabled.

Five dailyAndCount pixels distinguish `install_readiness`, `upgrade_readiness`, `background_wake`, `background_load_retry`, and `late_document_reload`. The common prefix is `web_extension_cpm_`, with `_macos` on macOS and standard platform/form-factor suffixes on iOS. The first four use `outcome=background_ready`: a successful slow callback after a navigation used the gate, or any successful error-6 retry. This is not a page ACK. The last uses `reload_started` and `response_received`; the latter requires an unambiguously attributed dashboard response after the exact WKNavigation returned by the accepted reload begins. A user navigation, including the same URL, or a response during the asynchronous safety check cannot claim reload success. No URL, tab ID, form value or raw error is sent. App tests independently observe the actual content-script ACK.

PR #7379 is stacked on #7376 (`alex/cpm-messaging-readiness-telemetry`). This test branch adds the app fixture, dedicated scheme/project entries and DEBUG app hooks above the production PR head. It has no separate production changes. The main PR contains none of this harness or its app hooks.
