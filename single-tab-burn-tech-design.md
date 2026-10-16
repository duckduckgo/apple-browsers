# iOS single-tab burn cleanup performance

## Background & Requirements

Burning a single tab closes the selected tab and clears data associated with the sites it visited. Fireproofing protects selected sites’ cookies and supported storage so users can keep their sessions. Correct deletion and preservation are essential to the browser’s privacy promise.

`FireExecutor` coordinates the burn. It prevents overlapping burns with `burnInProgress`; requests received while another burn is active are dropped. The animation runs independently of cleanup, so the end of the animation does not necessarily mean another burn can begin.

An accepted request looks up visited domains before closing the tab. Website-data cleanup continues asynchronously, keeping the executor busy. The investigation found two avoidable costs in this cleanup: matching cookies are deleted serially, and one cleanup stage enumerates more website-data types than it removes. Reducing these costs should shorten the interval during which another burn is rejected. It does not establish why the first accepted tab might appear not to close.[1]

Requirements:

- Reduce scoped cleanup latency without weakening deletion, Fireproofing, domain matching or completion guarantees.
- Gate behavior changes behind a remotely controlled flag that defaults off.
- Measure requests, rejected requests and burn duration in both flag states.
- Preserve full-scope burn behavior and the protection against overlapping burns.
- Keep progress indicators and other UX changes out of scope.

## Problem Statement

Reduce avoidable website-data cleanup time during single-tab burns so the executor becomes available sooner, while preserving exactly which data is deleted and protected.

## Recommended Approach

The worktree implements two targeted optimizations using existing WebKit APIs and Swift concurrency. No new technology or service is introduced.

1. **Add a reversible feature flag.** Register `singleTabBurnOptimization` under `iOSBrowserConfig`, disabled by default. Require a `FeatureFlagger` dependency in `WebCacheManager` and pass it from `MainCoordinator`; do not obtain it through a singleton fallback. Read the flag once when scoped cleanup starts. Full-scope cleanup retains its existing implementation.

2. **Narrow website-data enumeration.** With the flag enabled, the safely-removable-data stage requests records only for the types that stage deletes. Apply the existing domain filter and remove the same data types as before. Cookies, local storage and IndexedDB continue through their existing dedicated cleanup stages.

3. **Bound concurrent cookie deletion.** Enumerate cookies and apply the existing scope and Fireproof filters. With the flag enabled, maintain at most eight outstanding deletions, starting another when one finishes. Await the entire task group before completing the stage. With the flag disabled, retain serial deletion. Keep migration and cleanup-stage ordering unchanged.[2][3]

4. **Instrument single-tab requests outside the flag.** Add the following PixelKit events for tab-scoped requests in both flag states. Emit the request event before the overlap guard so rejected attempts are counted. Measure elapsed time with a monotonic clock and emit the finished event after the accepted burn’s work returns.

   | Event | Parameters | Purpose |
   |---|---|---|
   | `fire_single-tab-burn_requested` | `optimization_enabled`, `dropped` | Compare the proportion of requests rejected while a burn is active. |
   | `fire_single-tab-burn_finished` | `optimization_enabled`, `duration_ms`, optional `tab_closure_ms` | Compare executor duration and time to tab closure. |

   Durations use inclusive upper-bound millisecond buckets: 100, 250, 500, 1,000, 2,000, 5,000, 10,000, 30,000, 60,000, 120,000, 300,000, and `more`. The optional tab-closure measurement includes the synchronous tab-closing path, including favicon cleanup. Timing starts at executor entry and excludes confirmation and animation setup. A finished event means the work returned; it does not certify that every underlying cleanup operation succeeded. Existing wide events retain stage outcomes.

5. **Validate correctness and performance before rollout.** Cover both flag states, flag changes between burns, bounded concurrency, completion waits, domain matching, Fireproofing and unchanged full-scope behavior. Use a repeatable, opt-in benchmark against real WebKit storage. Complete physical-device and UI checks before drawing conclusions about user-visible latency.

6. **Roll out through privacy configuration.** Start with a controlled comparison, review duration distributions and dropped-request rates, and expand only if deletion behavior remains correct and field measurements support the improvement. Disabling the flag restores the original scoped cleanup path for subsequent calls; instrumentation remains active.[4]

## Notes

[1] **Keep the overlap guard.** Allowing concurrent burns would change shared cleanup-state guarantees. Queuing retries or showing indeterminate progress would be separate behavior or UX changes. This design addresses the identified cleanup costs and does not claim to resolve every reported tab-closure failure.

[2] **Keep cookies separate from website-data-record deletion.** Cookies are conceptually Fireproofable, but their deletion uses cookie-domain matching, including subdomain scope. Website-data records use registrable-domain matching. Moving cookies into that record-based removal path could broaden deletion beyond the existing cookie scope.

[3] **Use bounded concurrency rather than unlimited fan-out.** Eight outstanding operations avoids creating one simultaneous deletion task per cookie. This limit produced a substantial improvement in the measured fixtures; it has not been established as optimal across devices. The implementation still waits for every selected deletion callback.

[4] **Flag attribution has two sampling points.** Metrics capture the flag at executor entry; `WebCacheManager` captures it when scoped cleanup starts. A flag change between those points can cause attribution to differ from the path used. Keep assignment stable during an individual burn when comparing cohorts. Changes between burns are supported and tested.

## Testing

### Automated correctness

Targeted tests were run through XcodeBuildMCP on the commissioned iPhone 17 / iOS 26.0 simulator. The earlier implementation run passed 120 tests across `FireExecutorTests`, `DataClearingPixelsReporterTests` and `WebCacheManagerTests`. The benchmark run subsequently passed its benchmark test and all 19 `WebCacheManagerTests` with zero failures.

Coverage includes both explicit flag states, changes between calls, the concurrency bound, waiting for the last deletion, cookie-domain and Fireproof filters, unchanged full-scope behavior, dropped-request instrumentation and duration parameters. Real WebKit checks verify deletion and preservation rather than relying only on mocked callbacks.

### Performance evidence

The opt-in benchmark times `WebCacheManager.clear(dataStore:forDomains:)`, the scoped website-data cleanup used by single-tab burn. It does **not** time the complete `FireExecutor` flow, history lookup, tab closure or animation. It uses a Debug simulator build, real persistent WebKit storage and mocked observations cleanup; migration is inactive.

Each workload ran 100 measured clears per flag state, with alternating execution order and five warm-ups per state. Every trial reset and reseeded the store outside the timed interval. Both workloads included local storage and IndexedDB for targeted, Fireproofed and unrelated origins.

| Workload | Flag off median | Flag on median | Median reduction | Flag off p95 | Flag on p95 |
|---|---:|---:|---:|---:|---:|
| 2,000 cookies across 40 domains; 1,000 deleted | 2,097.88 ms | 85.77 ms | 95.9% | 4,133.29 ms | 92.38 ms |
| 12 cookies across 3 domains; 4 deleted | 16.67 ms | 13.29 ms | 20.3% | 26.87 ms | 20.99 ms |

All 400 measured clears and 20 warm-ups passed exact cookie deletion/preservation checks and storage deletion/retained-content checks. Mean, median and p95 improved in both workloads. One enabled small-workload sample took 86.61 ms, exceeding the disabled maximum of 37.62 ms; worst-case improvement is not established. No measured samples were discarded.

The [performance report](/Users/brindy/Kainban/Files/brindy/improve-single-tab-burn-speed/burn-benchmark-report.md) contains fixture details, raw-data references, statistical analysis and XcodeBuildMCP rerun instructions. The benchmark skips unless `RUN_SINGLE_TAB_BURN_BENCHMARK=1`; use `BURN_BENCHMARK_ITERATIONS=100` and `BURN_BENCHMARK_WARMUPS=5` to repeat this run.

### Remaining QA and validation

Repeat with the flag off and on:

1. Burn a tab that visited multiple sites; confirm closure, scoped deletion and preservation of an unrelated tab’s session.
2. Include Fireproofed sites, subdomains and parent-domain cookies; confirm protected data survives and matching unprotected data is removed.
3. Exercise current/background tabs, browsing/tab-switcher entry points, normal/Fire tabs and Duck.ai tabs.
4. Retry rapidly while cleanup is active; confirm the existing overlap behavior and requested/dropped/finished metrics.
5. Burn all tabs and change the flag between burns without restarting; confirm the expected paths.
6. Measure complete burn latency on physical devices, including older devices and larger cache populations. Simulator cleanup timings alone do not establish the production improvement.

Strict lint passed using installed SwiftLint because Mint was unavailable. Pixel formatting passed. The pinned pixel-schema and wide-event validation commands remain to be rerun after dependency installation succeeds; the earlier installation was blocked by network resolution. A separate reference-test run was blocked by the missing `privacy-reference-tests/storage-clearing/tests.json` fixture.

## Additional Considerations

### Privacy

Deletion scope and retention behavior are unchanged. The new telemetry reports flag state, whether a request was dropped, and bucketed durations. It adds no URLs, domains, user identifiers or raw timings. Treat the new measurement as part of privacy review and use the Privacy Triage Template for team input before rollout; this document does not imply that triage has been filed or approved.

### Security

The change uses existing WebKit deletion APIs without introducing permissions, endpoints or storage. The primary correctness risk is deleting the wrong data or returning before deletion finishes. Existing filters, bounded concurrency and completion tests address those risks. The overlap guard remains in place.

### Site Breakage

Overbroad deletion could sign users out of unrelated or Fireproofed sites. Retaining the existing cookie/domain filters and separate storage paths limits that risk. Tests verify retained contents as well as deletion; manual QA must also confirm sessions survive. The feature flag provides rollback for subsequent cleanup calls.

### Experimentation

Compare dropped requests divided by total requested events and the distributions of executor duration and tab-closure duration, grouped by flag state. Use existing cleanup outcome telemetry alongside timing so speed does not mask deletion failures. These are aggregate events, not identifiers for joining individual burns. Bucketed measurements will not resolve every small improvement, particularly below 100 ms.

Stable cohorts and comparable app/OS/device populations are needed to interpret differences. Review experiment setup and success criteria before rollout. Field data is needed to establish whether shorter cleanup reduces rejected attempts in practice.

### Operational

No hardware, service or CI deployment changes are required. Remote enablement belongs in `duckduckgo/privacy-configuration`; embedded configuration remains unchanged. The flag’s tracking-task URL still needs to be supplied.

The number of outstanding cookie deletions stays bounded at eight as cookie counts grow. Cookie enumeration and filtering still scale with the store’s cookie population. No new retries, timeouts or error suppression are introduced: existing cleanup outcomes and orchestration behavior remain in use. If WebKit delays callbacks, cleanup still waits; this optimization is not a recovery mechanism for hung operations. Disabling the flag does not interrupt an in-progress call that already sampled it.

Existing telemetry plus the new request/duration events provide rollout monitoring. This client-side change introduces no new service SLI/SLO.

### Localization / Internationalization

There are no new user-facing strings or UI elements. Domain normalization and matching remain unchanged. No new localization work is required; existing domain-handling tests remain applicable.
