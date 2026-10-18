# CPM recovery after Network process replacement

Review-only branch: `codex/cpm-network-process-integration-tests`. The production change is in
`alex/cpm-network-process-recovery`, based directly on `alex/cpm-messaging-readiness-telemetry`.
This harness and its DEBUG app hooks must stay out of the production PR, following #7379's split.

On macOS 15.4 or later, open `DuckDuckGo.xcworkspace`, select **CPM Integration Tests** and **My Mac**,
and choose **Product → Test**. The scheme opts into the isolated fixture automatically.

Four app-hosted tests exercise real AppDelegate lifecycle callbacks, browser windows/tabs, native
handlers, and system WebKit:

- `testNetworkProcessCrashKeepsNavigationsWorkingAcrossTabsAndWindows`: four healthy tabs in two
  windows, two successive SIGKILLs of the owned Network process, and healthy first/subsequent
  navigations after each crash. No post-crash sleep or replacement wait is inserted. Action and response
  policy checks must repair the stale background before document-start scripts run, while the
  extension context stays identical.
- `testNetworkProcessCrashRecoversExistingDocumentsWithoutExtensionReload`: three healthy documents
  in two windows, a Network-process crash and no navigation, followed by another real CPM `init`
  from each existing content script. Require a fresh native dashboard and actual page `initResp`,
  unchanged document URLs and the original extension context. The fixture requests that second
  `init`; this does not claim that production automatically retries an already lost message.
- `testNetworkRecoveryWorksWithDiagnosticsAndStartupGateDisabled`: the first post-crash navigation
  works with the diagnostics recorder absent, delegate proxy off and startup navigation gate off.
- `testRuntimeKillSwitchPreservesContextAndAllowsRecoveryWhenEnabled`: disable the production flag,
  crash the Network process and verify lost replies with the original background PID retained;
  enable the flag in that same manager and require background restart, existing-document response,
  and a healthy subsequent navigation without replacing the context.

Select **CPM Integration Tests - Fixes Disabled** and test again. It selects the first three tests
and sets `CPM_APP_INTEGRATION_DISABLE_NETWORK_RECOVERY=1`; the fixture disables the actual production
`webExtensions.cpmNetworkProcessRecovery` flag. Expect **3 failed, 0 passed, 0 skipped** for missing
native/page responses. A compile failure, crashed test host, setup error or skipped test is not the
negative-control result. The runtime-toggle test is excluded because it explicitly enables recovery.
Return to **CPM Integration Tests** and require **4 passed, 0 failed, 0 skipped** again.

Both schemes use the same app/XCTest binaries. For command-line verification, first build/run the
normal scheme with `xcodebuild test`, specifying a dedicated `-derivedDataPath`, and then run both
schemes with `xcodebuild test-without-building` and that same path. Keep the normal scheme's negative
control environment override unset. M4 extension reload and the graveyard treatment are explicitly
disabled in every scenario, and all other relevant flag states are arranged by the fixture.

The Network process belongs to a nonpersistent test data store shared only by this fixture's views
and extension. The production extension ZIP remains unchanged. An extracted copy observes actual
`initResp` delivery; the only explicit message injection asks an existing content script to send a
normal `init` again. The loopback server serves local documents, native extension pixels are
intercepted, and JSON attachments preserve page/native responses and diagnostics. The host requires
no existing windows or pins and restores flags/releases owned resources during cleanup.

The pre-fix telemetry-base run reproduces both failed navigation and failed existing-document
scenarios. These forced macOS process failures do not identify every natural production trigger
or validate real iOS background suspension/jetsam. Same-PID worker death and error-6/slow-start
recovery are outside this fix.

## Verified local result

On 18 October 2026, macOS 26.7.1 / Xcode 27.1: enabled scheme **4 passed**, disabled scheme
**3 functional failures**, then enabled scheme **12/12 executions passed** across three iterations
of all four methods, without rebuilding. All 4,717 app/XCTest bundle files stayed byte-identical.
The earlier telemetry-base reproduction failed both scenarios. The response-policy guard was
required to close a separately reproduced action-to-response Network-process replacement race.
The full shared package passed **774 tests**; production macOS and iOS app builds passed, and the
separate production macOS app passed deep/strict code-signature verification.

The test host's root app and XCTest signatures verify. A whole-bundle deep check of this test-only
Debug fixture reports missing Swift module metadata in its copied DBP helper framework. The
separately built production app passes that same deep check; none of the app fixture hooks or
project entries are part of the production branch.
