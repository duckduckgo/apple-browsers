# CPM stable-origin app integration tests (review only)

Production branch: `alex/cpm-p3-stable-base-url`, based on telemetry #7376.
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

The ten methods cover repeated immediate navigation after reload, 20,000 cacheable resources,
full and lightweight data-clear reloads, runtime OFF/ON, storage preservation, version upgrade,
background crash, Network crash followed by explicit reload, and web-page resource privacy.
Every healthy probe requires both the content script's real `initResp` and the real native
CPM dashboard notification. The ordinary-reload/cache regressions navigate immediately, without
a readiness wait. Upgrade/rollback controls wait for an actual background-load callback to
isolate P3 from the P4 startup race; a reported load error fails immediately.

A passive observer records the real WebKit `_renameOrigin:to:forDataOfTypes:completionHandler:`
calls for the fixture's own UUID store. It forwards the original arguments/completion unchanged,
adds no delay, and restores the implementation in teardown. Normal enabled reloads require zero
migration calls. Data clear intentionally rotates/persists the private origin; disabling the
feature prepares a fresh saved origin for a later re-enable, avoiding deleted worker registrations.

Each method owns fresh persistent website/controller stores and temporary extracted extension
resources outside the globally swizzled test folder. Only the copy is instrumented: DOM receipt
marks, an existing-document re-init event, and a small storage round-trip listener. The production
ZIP and telemetry definitions are untouched. Fixture servers bind only to loopback.

Teardown captures evidence, ends owned HTTP documents, closes only fixture windows, releases
their models, unloads the fixture extension, clears its data through WebKit APIs,
waits for Tab/browser UI deallocation, closes any remaining unowned WebKit page, then
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

Verified locally on macOS 26.7.1: ON 10/10; OFF 7 pass / 3 expected origin-continuity
failures; restored ON 30/30 executions. No skips or host restarts. All 50 owned persistent
stores were removed, and all 5,210 app/XCTest bundle entries stayed unchanged across the cycle.
Raw xcresults, JSON attachments and bundle manifests are retained locally under
`/private/tmp/cpm-p3-20261019/acceptance-v4`.
