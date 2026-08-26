# Prompt: in-depth review of the iOS On-site Permission Manager design (round 2)

You are an independent senior reviewer working in the DuckDuckGo apple-browsers monorepo (repo root = your working directory). Your feedback goes to the DRI, who will act on it — be constructive, concrete, and evidence-based. **You have no access to Asana, Figma, or the network.** Do not attempt to open any asana.com or figma.com links; treat `docs/on-site-permission-manager/requirements.md` as the authoritative product requirements and `docs/on-site-permission-manager/tech-design.md` as the proposal under review. Verify claims against the codebase, not against the documents' own assertions.

**Context:** this is the second review round. A first review already moved the design from a two-package macOS extraction to its current shape: iOS-standalone, one local package (`iOS/LocalPackages/SitePermissions`, single production target + tests) with thin app-target glue, a 7-PR stack, no macOS changes. Your job now is to (a) validate all the facts the revised design rests on, and (b) either confirm this is the best available approach or show a better or simpler one, with evidence.

**Settled product decisions** (DRI-owned; treat as fixed unless they create a technical contradiction or you find repo evidence they cannot work — do not relitigate on taste): global Never Allow is absolute (beats stored per-site Always); user-reset "Ask Each Time" rows stay listed until removed; recovery flows ship inside the dialog and sheet PRs; no macOS changes in v1. Implementation choices are all fair game.

## Tasks

### 1. Fact-check every repo claim

The design cites many file:line facts and precedents. Verify each and report **CONFIRMED** or **WRONG (+ correction)**. At minimum:

- `iOS/DuckDuckGo/TabViewController.swift:3938` — current media-capture matrix incl. the Duck.ai mic branch; `SharedPackages/AIChat/Sources/AIChat/iOS/AIChatWebViewController.swift:267` — `.deny` default.
- `iOS/Core/FullScreenVideoUserScript.swift:23` as the page-content-world / all-frames user-script precedent; `SharedPackages/EventHub` `WebEventsHandler` registered at `iOS/DuckDuckGo/UserScripts.swift:178-182` as the package-defined, app-registered precedent.
- `UserScript.loadJS(_:from:)` + `Bundle.module` for shipping JS from a package (`SharedPackages/BrowserServicesKit/Sources/UserScript/UserScript.swift`).
- `KeyedStoring` API shape (`SharedPackages/Persistence/Sources/Persistence/KeyValueStoring.swift`) and the `iOS/DuckDuckGo/TextZoomStorage.swift` per-domain precedent.
- `iOS/DuckDuckGo/Fire/FireWorkers/FireExecutorWorker.swift:28` — concurrent normal+fire dispatch for `.all`; `iOS/Core/Fireproofing.swift` — eTLD+1 storage.
- `iOS/DuckDuckGo/SettingsMainSettingsView.swift` — locale-sorted entries with nil-hiding `build:` closures; `iOS/DuckDuckGo/BrowsingMenu/SheetPresentationMenu/BrowsingMenuBuilder.swift:220` — hard-coded seventh-item detent.
- `iOS/LocalPackages/SetDefaultBrowser` — package shape and the event-enum → app-side `EventMapping` pixel pattern; `SyncUI-iOS` — `AVCaptureDevice` use and 26-locale package localization.
- Scheme facts: `TestableReference` wiring and `SKIP_SNAPSHOT_TESTS=1` in `iOS/DuckDuckGo-iOS.xcodeproj/xcshareddata/xcschemes/iOS Browser.xcscheme`; package registration cost per commit `0d63fbb8f3` (AppRouting).
- `iOS/LocalPackages/FeatureFlags-iOS/.../FeatureFlag.swift` — `Config`-based flag shape.
- **API availability vs deployment target:** `WKWebView.cameraCaptureState`/`microphoneCaptureState` KVO and `requestMediaCapturePermissionFor` against the iOS app's actual minimum deployment target (check the xcconfig/pbxproj) — flag anything the design assumes but the floor doesn't support.

### 2. Architecture verdict

Is the single local package + thin app glue the best shape for this component list, given the repo's real conventions? Compare once more against app-target-only and any hybrid you find better. Is the package earning its one-time setup cost?

### 3. Overcomplication hunt (given the current architecture)

Judge each against what repo primitives already provide: the per-tab coordinator (vs simpler inline decision logic); `SystemPermissionService` as an abstraction (vs direct AV/CoreLocation calls + a test seam); actor-owned store (vs MainActor); the permission-key contract (vs simpler); the `.ask`-marker machinery required by the kept-rows decision; the 7-PR split (merge or resplit better?). Name anything speculative.

### 4. Alternative angles round 1 did not examine

- Ship camera/mic first and geolocation later behind a separate subfeature — does the PR stack allow a cheaper v1 cut line?
- The shim: should it be built on the existing content-scope-scripts / `ContentScopeUserScript` isolated+page infrastructure instead of a bespoke `WKUserScript`? Check what C-S-S actually provides on iOS before answering.
- Should the model reuse BSK's existing permission DTOs (`SharedPackages/BrowserServicesKit/Sources/PrivacyDashboard/Model/AllowedPermission.swift`, `PermissionAuthorizationState.swift`) instead of defining new enums?
- Anything else in BSK/SharedPackages that already models or stores per-site state that the design reinvents.

### 5. Delivery plan and release safety

Sanity-check dependencies, estimates, and decision gates in tech-design §5. Then try to falsify the release-safety claims: flag-off call-site matrices, shim registration, detent change, pbxproj/scheme edits, the fire-worker-burns-while-off exception.

### 6. Requirements coverage

Any FR the design still fails to implement, any ambiguity that will bite, and any new contradiction introduced by the recent decisions (global-absolute precedence, kept `.ask` rows, merged recovery).

## Output format

1. Fact-check table: claim → CONFIRMED/WRONG → evidence (file:line).
2. Overall verdict: **best available approach** or **change X**, with reasoning.
3. Better-approach and simplification findings, ranked by impact, each with concrete evidence and estimated savings.
4. Risks the design misses.
5. Questions for the DRI.

Feedback only — do not rewrite the documents or change any code.
