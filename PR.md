Task/Issue URL: https://app.asana.com/1/137249556945/task/1219231427593373

Depends on #7376 (`alex/cpm-messaging-readiness-telemetry`).

### Description

Keep CPM's private extension origin stable across reloads and app launches, avoiding WebKit's origin migration before content-script injection. Retain a private random origin per installation, rotate it after data clearing and rollback, and apply this only to registered embedded CPM installations without web-accessible resources.

This addresses the origin-change startup path investigated under P3. It does not establish that every production report of a loaded context without a background view has this cause.

Enabled by default on iOS and macOS, with remote kill switch `webExtensions.cpmStableBaseURL`. Disabling applies when the next extension context is created, including after an app restart; an already loaded context keeps its origin. Fire gets a fresh persisted origin so WebKit cannot reuse a deleted service-worker registration. Re-enabling after rollback also uses a fresh saved origin. Remote rollout/overrides belong in `duckduckgo/privacy-configuration`.

### Testing Steps

The app harness and DEBUG hooks live only in the [review-only integration branch](https://github.com/duckduckgo/apple-browsers/tree/codex/cpm-p3-integration-tests); that branch must not be merged into main.

1. On the production branch, run `swift test --package-path SharedPackages/WebExtensions --skip-update` → all tests pass, including P3 origin-policy and runtime flag regressions.
2. Run `git fetch origin codex/cpm-p3-integration-tests`.
3. Switch to `codex/cpm-p3-integration-tests`.
4. On macOS 15.4 or later, open `DuckDuckGo.xcworkspace` in Xcode and select **My Mac**.
5. Run **CPM Integration Tests** → reload, disk load, 20,000-entry persistent cache, runtime rollback, extension storage, version upgrade, data clear, process crashes and resource privacy tests pass.
6. Run **CPM Integration Tests - Fixes Disabled** → the three origin-continuity regressions fail because the original randomized origin returns. Host crashes, skips and setup failures do not count as this result. A missing CPM reply is not required: this Mac has not reproduced the complete production P3 failure.
7. Run **CPM Integration Tests** again → all tests pass again on the same app/XCTest binaries.
8. Return to `alex/cpm-p3-stable-base-url` for production review.

Each app test uses its own persistent website/controller stores. A passive observer records actual WebKit origin-migration calls without changing their arguments or completion. The tests require actual page `initResp` and native dashboard delivery. They record the origin, startup observations and any real failure snapshots. No synthetic startup delay is injected.

### Verified Results

- WebExtensions package: 784 tests passed, no failures or skips.
- Same signed app/XCTest binaries: ON 10/10; OFF 7 passed with exactly the 3 origin-continuity methods failing; restored ON 30/30 executions (each method repeated three times). All 5,210 bundle entries stayed unchanged.
- Actual WebKit origin migration: zero on ordinary/cache reloads with the flag ON; returns with the flag OFF. Each cache run completed 20,000 resource-body reads in the owned persistent store and verified disk-cache data.
- Real background/Network process kills, Fire, runtime rollback, extension storage, upgrade and resource-access controls passed. All 50 owned persistent stores were removed, with no host crash, restart or skipped method.
- Production macOS and iOS Simulator builds, strict lint for all changed Swift files, project/scheme validation and production macOS signature verification passed.

These are local macOS app-integration results and an iOS build, not an iOS runtime reproduction or a claim that the full production P3 no-background failure was reproduced. The final source diff was reviewed again after fixing the data-clear and OFF→ON worker-origin regressions found during validation.

### Impact

Medium: changes CPM's internal origin selection on context creation.

#### What could go wrong?

- Reusing an origin could change service-worker recovery → exercise background crash, Network crash followed by explicit extension reload, version upgrade and data-clear reload.
- Rollback could lose extension settings → exercise storage across runtime OFF/ON reloads.
- A stable origin could expose an extension installation to sites → retain the random installation UUID, exclude web-accessible resources and test that a normal page cannot read extension resources.

### Quality Considerations

The flag is read for each new context; live origins are never mutated. Invalid/non-UUID installation identifiers fall back to WebKit's original behavior. Other embedded types and ordinary third-party installations retain their original origin policy. The optional saved origin is backwards compatible with existing installation records. Bundled ZIPs, dependency pins and telemetry definitions are unchanged.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
