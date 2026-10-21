# CPM stable-origin app integration tests (review only)

Production branch: `alex/cpm-p3-stable-base-url`, now based on `release/ios/7.243.0` after telemetry #7376 merged.
This branch adds the app fixture, schemes and DEBUG hooks only; do not merge it into main.
Use macOS 15.4+, a graphical login session, and the project's normal Apple Development signing.

In Xcode, open `DuckDuckGo.xcworkspace`, select **My Mac**, then run:

1. **CPM Integration Tests**: all 10 methods must pass.
2. **CPM Integration Tests - Fixes Disabled**: three origin-continuity methods must fail, while the other controls pass.
3. **CPM Integration Tests**: all 10 must pass again without changing/rebuilding Swift code.

The schemes explicitly configure the real `webExtensions.cpmStableBaseURL` flag. The disabled
scheme does not replace production methods or annotate failures as expected. It restores
random origins. A red origin assertion/migration observation proves that the startup work
returns; it is not evidence that this Mac reproduces every production P3 no-background timeout.

The ten explicitly selected methods cover repeated immediate navigation after reload, 20,000 cacheable resources,
full and lightweight data-clear reloads, runtime OFF/ON, storage preservation, version upgrade,
real background-process SIGKILL, Network crash followed by explicit reload, and web-page resource privacy.
The background-crash case enables the existing error-6 retry and confirmed-hang recovery.
If native recovery fails, two real navigation timeouts trigger automatic context replacement;
its failed worker origin must rotate and the next navigation must receive both real replies.
All other P3 cases explicitly disable the independent recovery flags.
Every healthy probe requires both the content script's real `initResp` and the real native
CPM dashboard notification. The ordinary-reload/cache regressions navigate immediately, without
a readiness wait. Upgrade/rollback controls wait for an actual background-load callback to
isolate P3 from the P4 startup race; a reported load error fails immediately.

A passive observer records the real WebKit `_renameOrigin:to:forDataOfTypes:completionHandler:`
calls for the fixture's own UUID store. It forwards the original arguments/completion unchanged,
adds no delay, and restores the implementation in teardown. Normal enabled reloads require zero
migration calls. Data clear and reload after WebKit background-load error 6 intentionally
rotate/persist the private origin; disabling the
feature prepares a fresh saved origin for a later re-enable, avoiding deleted worker registrations.

Each method owns fresh persistent website/controller stores and temporary extracted extension
resources outside the globally swizzled test folder. Only the copy is instrumented: DOM receipt
marks, an existing-document re-init event, and a small storage round-trip listener. The production
ZIP and telemetry definitions are untouched. Fixture servers bind only to loopback.

Teardown captures evidence, ends owned HTTP documents, closes only fixture windows, releases
their models, unloads the fixture extension, clears its data through WebKit APIs,
drains XCTest autorelease pools and waits for owned window/Tab/browser UI deallocation,
preserves AppKit's shared Function Row panel, closes any remaining unowned WebKit page, then
terminates only the test host's owned Network session and removes the owned UUID store.
No user profile wipe, global process kill, guard bypass or fabricated monitor callback is used.

Each method retains a JSON attachment with real probes, raw local diagnostics, actual migration
calls, recorded production pixels and the owned persistent-store UUID. App guards remain enabled.
Forced macOS process faults and the cache experiment do not establish the natural iOS P3 cause.

Command-line builds use the same scheme and configured signing, for example:

```sh
xcodebuild test -workspace DuckDuckGo.xcworkspace \
  -scheme 'CPM Integration Tests' -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/cpm-p3-review \
  -resultBundlePath /private/tmp/cpm-p3-review-on.xcresult \
  -skipPackagePluginValidation -skipMacroValidation
```

Use fresh result paths for subsequent runs. For a strict identical-binary comparison, build once
with `build-for-testing`, then use `test-without-building` with the same products for both schemes.

Historical run before the macOS 27 harness corrections, on macOS 26.7.1: ON 10/10; OFF 7 pass / 3 expected origin-continuity
failures; restored ON 30/30 executions. No skips or host restarts. All 50 owned persistent
stores were removed, and all 5,210 app/XCTest bundle entries stayed unchanged across the cycle.
Raw xcresults, JSON attachments and bundle manifests are retained locally under
`/private/tmp/cpm-p3-20261019/acceptance-v4`.


## macOS 27 research selection

The default schemes select exactly ten acceptance methods. For cache characterization, edit
**Test → Info** in each scheme to select only
`CPMStableBaseURLIntegrationTests.testP3ResearchPersistentCacheReload`, then build once and
use **Test Without Building** for OFF and ON. The bounded method requires healthy controls,
20,000 actual resource-body reads, disk-cache records and three immediate reload measurements.
An optional disk-startup counterpart is `testP3ResearchPersistentCacheDiskLoad`.

A P3 observation has a loaded context, `load>base_url_changed`, no background view,
no extension scripts, and neither native dashboard nor page `initResp` at timeout.
A healthy measured response is a valid negative result. Setup/cleanup failures and process
restarts do not establish P3. The marker observes the existing production `initResp` handler;
it does not wrap WebKit's runtime event API, fabricate replies or delay startup.

Verified final code on **macOS 27.0 (26A428) / Xcode 27.0 (27A266a)**:
ON **10 passed / 0 failed / 0 skipped**, OFF **7 passed / 3 expected origin-continuity failures / 0 skipped**,
restored ON **10 passed / 0 failed / 0 skipped**. All 30 unique owned stores were removed;
all 5,222 signed app/XCTest entries matched before and after all phases. Two additional
standalone SIGKILL controls (ON and OFF) each passed with no skips and removed their stores.

The OFF acceptance cache case reproduced the full P3 signature after 4.57 seconds:
loaded context, `load>base_url_changed`, no background view/scripts, no native/page reply,
one actual origin migration. Both ON cache cases replied on both channels after 0.37 and
0.30 seconds with no migration. Each case completed 20,000 actual body reads and server
send completions, passed its healthy control and verified disk-cache data. No synthetic
startup delay or process hold was used. These are observations, not performance benchmarks;
the VM host SSD has recorded I/O errors. Natural iOS reproduction remains unverified.

The final raw xcresults, JSON evidence and hash checks are retained under
`/private/tmp/cpm-p3-vm27-20261020/research-v9-acceptance-results` and
`/private/tmp/cpm-p3-vm27-20261020/research-v9-crash-results`.


## Error 6 across two real app processes

`testBackgroundError6AcrossAppRelaunch` is deliberately outside the ten-method selection.
Build once with `build-for-testing`, then run the dedicated driver in a graphical login session:

```sh
python3 macOS/IntegrationTests/CPM/run-relaunch.py \
  --products /private/tmp/cpm-p3-review/Build/Products \
  --plan '/private/tmp/cpm-p3-review/Build/Products/CPM Integration Tests_macosx27.0-arm64.xctestrun' \
  --output /private/tmp/cpm-p3-relaunch-results
```

Use the actual generated xctestrun filename for your SDK and a new output directory. The runner
compares signed app/XCTest hashes before and after each phase; for a transferred bundle, pass
`--manifest` with the trusted host's `bundle-before.json`.

For each explicit P3 flag state, prepare kills only the owned background PID with SIGKILL and
navigates through the real content script. Native recovery can succeed; the bounded attempts
must observe a real WebKit error 6 notification to qualify this scenario. No synthetic error
or recovery callback is injected. P1/P2 recovery stays disabled, so no reload can mask the bug.
Prepare verifies the stored next origin without mutating or replacing the live context, and
preserves only the owned registry, extension resources and website store. The first app process
must exit. Resume starts a different app PID against the same installation/store and verifies a
fresh origin, native/page replies and real browser.storage.local persistence. It then removes
the owned store and registry. Window, Tab and browser-controller deallocation guards remain on.
Both phases must pass for ON and OFF. Missing error 6 is a failed reproduction, never a pass.
A failed prepare that never reaches the checkpoint cannot count as a reproduced metadata bug.


Verified error-6 review fix (`a9f841cf83`) on macOS 27.0 (26A428), Xcode 27.0 (27A266a):
all four prepare/resume stages passed with no failures or skips, with real error 6 after owned
background SIGKILL and different app PIDs. ON used the saved replacement origin; OFF did not
persist an error-triggered replacement. Real extension storage survived both relaunches, both
reply paths were healthy, both owned stores were removed, and all 5,222 signed app/XCTest
entries matched before and after every stage. The previous PR code reproduced missing origin
metadata and reuse on the next app launch; that full restart itself restored messaging.
Raw before/after xcresults and observations are retained under
`/private/tmp/cpm-p3-restart-20261022/baseline-results` and `fixed-relaunch-results`.
