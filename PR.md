Task/Issue URL: https://app.asana.com/1/137249556945/project/1202406491309510/task/1219531810004073

Base: `alex/cpm-messaging-readiness-telemetry` (#7376), the same base as #7379. This change is independent of #7379's startup/wake fixes and does not include the old #7381 stack.

### Description

Cookie Pop-up Management can stop answering across all tabs after WebKit replaces its Network process, while the extension background still appears loaded. Restart the affected background while preserving the extension context and the content scripts already injected into open documents. Check before navigation, again before the main-frame HTTP response is allowed to execute document-start scripts, and periodically while that background exists.

The independent `webExtensions.cpmNetworkProcessRecovery` flag defaults to disabled on iOS and macOS and is read immediately before recovery. Runtime disable cancels periodic checks; flag updates resume recovery on the existing background without navigation, retaining the original Network-process baseline. Rollout is controlled by that subfeature in `duckduckgo/privacy-configuration`; this change does not enable it remotely.

### Testing Steps

#### Manual reproduction: kill the Network process

Use the production worktree `alex/cpm-network-process-recovery`; the integration-test branch is not required for these steps.

1. On macOS 15.4 or later, run the **macOS Browser** scheme in **Debug** on **My Mac** from `DuckDuckGo.xcworkspace`. Enable internal user state if required by **Debug → Feature Flag Overrides**. Under **Web Extensions**, explicitly set:

   | Flag | Reproduce failure | Verify fix |
   | --- | --- | --- |
   | `webExtensions` | ON | ON |
   | `embeddedExtension` | ON | ON |
   | `webExtensionStateRestorationGate` | ON | ON |
   | `cpmDiagnosticsRecorder` | ON | ON |
   | `cpmBackgroundDelegateProxy` | ON | ON |
   | `cpmNetworkProcessRecovery` | **OFF** | **ON** |
   | `cpmMessagingHangRecovery` | OFF | OFF |
   | `cpmBackgroundGraveyardTreatment` | OFF | OFF |

2. Enable Cookie Pop-up Management in Settings and leave **Simulate CPM Breakage** off. Restart this test browser after arranging the initial flags. Open [the autoconsent test page](https://privacy-test-pages.site/features/autoconsent/) in several tabs across two windows. Establish a healthy baseline: the test button changes to **I was clicked!** and the privacy dashboard reports **Cookies Managed**. These are the same visible checks used in `macOS/UITests/AutoconsentUITests.swift`.
3. In this app run's Xcode console, find the latest `[CPM Diagnostics] Background web view created` line and copy its positive `networkProcessPID`. This is the **Network** PID; the **CPM Background WebContent PID** menu item identifies a different process. Keep the browser running, unpaused. Perform the crash while the background is still loaded, within 15 seconds of the successful baseline navigation; reload the baseline page first if needed and confirm the current PID again.
4. Replace `NETWORK_PID` in both commands below with that numeric PID. Inspect the first command's output and confirm that it identifies `com.apple.WebKit.Networking` for this test app, then execute the second command to kill that specific process:

   ```sh
   ps -p NETWORK_PID -o pid=,comm=
   kill -9 NETWORK_PID
   ```

5. Immediately navigate/reload the test pages in the existing tabs and load the page in a new tab/window. Do not wait for Network-process replacement before the first navigation: that also exercises the action-to-response race. With recovery **OFF**, expect CPM to stop responding: the freshly loaded page's test button stays unclicked and its fresh **Cookies Managed** result is absent. Continue navigating across tabs within the background's 30-second idle window; a long quiet interval can let WebKit unload/recreate the background and conceal the failure. Do not use Fire, reload the extension or relaunch during this observation.
6. Enable `cpmNetworkProcessRecovery`, restart the test browser to establish another healthy baseline, and repeat steps 2–5 using the **new current Network PID**. With recovery **ON**, expect the first and subsequent post-crash navigations to manage the test button and show **Cookies Managed**. The console should show `[CPM Recovery] Restarted embedded background after Network process replacement` and a background creation with a changed `networkProcessPID`. Repeat the kill/navigation cycle once more using the latest PID.
7. Verify runtime toggling in the same app session: switch recovery **OFF**, establish a healthy baseline and kill its current Network process again. Confirm the failure on fresh navigations, then switch recovery **ON** without relaunching, Fire or extension reload. Expect the recovery log without another navigation; reload the test page and confirm CPM works again. Switching recovery OFF also cancels periodic checks, covered directly by the shared unit regressions.
8. Restore the flag overrides changed for this test when finished. `cpmNetworkProcessRecovery` defaults to OFF; remote rollout is a separate privacy-configuration change.

#### Automated reproduction and regression checks

The production branch contains the shared unit regressions. As in #7379, the app harness, dedicated schemes and DEBUG app hooks live only on the [review-only branch `codex/cpm-network-process-integration-tests`](https://github.com/duckduckgo/apple-browsers/tree/codex/cpm-network-process-integration-tests); that branch must not be merged into main.

1. On the production branch, run the shared package tests:
   ```sh
   swift test --package-path SharedPackages/WebExtensions --skip-update
   ```
2. Switch to the review branch:
   ```sh
   git fetch origin codex/cpm-network-process-integration-tests
   git switch codex/cpm-network-process-integration-tests
   ```
3. On macOS 15.4 or later, open `DuckDuckGo.xcworkspace` in Xcode and select **My Mac**.
4. Test the **CPM Integration Tests** scheme. Expect **4 passed, 0 failed, 0 skipped**: repeated Network-process crashes across four tabs/two windows; existing-document messaging; recovery with diagnostics/startup gate disabled; and runtime flag disable/enable without replacing the context.
5. Test **CPM Integration Tests - Fixes Disabled**. Expect **3 failed, 0 passed, 0 skipped**, from missing dashboard/page responses. This scheme disables the actual production recovery flag for the first three scenarios. Setup failures, host crashes or skips are not the expected result.
6. Test **CPM Integration Tests** again. Expect all **4 to pass** again. Both schemes use the same app/XCTest binaries; the fixture switches the flag. See `macOS/IntegrationTests/CPM/README.md` on the review branch for command-line and scenario details.
7. Return to `alex/cpm-network-process-recovery` for production review.

Verified locally on macOS 26.7.1 / Xcode 27.1:

- Telemetry-base reproduction: **2 functional failures, 0 skips**. The additional action/response race also failed before the response guard was added.
- Full WebExtensions package: **778 passed, 0 failed**, in two complete runs; 20 new unit regressions, including no polling while disabled, runtime cancellation/resumption and owner release during active polling.
- Same app/XCTest binaries: **ON 4 passed → OFF 3 expected functional failures → ON 12/12 executions passed** (all four tests repeated three times), with no skips or expected-failure annotations. All 4,717 bundle files were byte-identical across the cycle.
- Separate production macOS app: **build passed and deep/strict code-signature verification passed**, without app harness hooks.
- Full production iOS app: **build passed** for the iOS 26.4 Simulator, including the platform response guard and feature flag.
- Strict SwiftLint: **0 violations** across production and harness changes. Dependency pins and bundled ZIPs are unchanged.

### Impact

Medium: restarts only the embedded CPM background after an observed Network-process replacement. Existing startup deadlines, M4 recovery and third-party extension behavior are unchanged.

#### What could go wrong?

- A replaced/unloaded background could be restarted → weak references, live context/view identity checks and unload cleanup discard its watch; unit tests cover replacement, unload and synchronous replacement during restart.
- A restart could repeat or outlive flag disable → clear the watch after a successful restart, check the runtime flag before acting, and cancel periodic checks when disabled; flag-update subscriptions resume an existing watch when re-enabled. Unit and app tests cover the transitions.
- WebKit SPI or a usable process identifier could be unavailable → guarded selectors and positive PID checks leave the background alone. No speculative restart is triggered by a missing identifier or an ordinary CPM timeout.

### Quality Considerations

The test fixture uses real app/WebKit navigation and native handlers, a nonpersistent owned data store, and SIGKILL of only its Network process. Success requires both the native dashboard and actual content-script `initResp`; M4 extension reload and the graveyard treatment are disabled. The production ZIP, dependency pins, telemetry schemas and feature defaults outside this new flag are unchanged.

Existing-document tests explicitly send another normal `init` through the original content script. This fix preserves that messaging capability; it does not automatically retry an already lost page message. Same-PID service-worker death, slow startup and error-6 recovery are outside this change. Forced macOS crashes do not establish every natural production trigger or validate iOS suspension/jetsam behavior. A crash after response policy can still lose an already in-flight message; this change does not promise replay of that message.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
