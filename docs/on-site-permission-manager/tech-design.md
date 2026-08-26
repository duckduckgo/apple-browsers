# [iOS] On-site Permission Manager — High-Level Tech Design

Companion to [requirements.md](requirements.md). This describes *how* we build the feature in the apple-browsers monorepo; the implementation plan (task-by-task) is a separate downstream artifact.

**Asana:** main task https://app.asana.com/1/137249556945/task/1213800892997347
**Revision note:** updated 2026-08-26 after an independent design review. Headline changes: v1 is iOS-standalone (**no macOS changes, no shared-package extraction**), one package with a single production target, a 7-PR stack, corrected flag-off semantics, and an explicit permission-key contract.

---

## 1. Current state (what we build on)

**iOS is greenfield.** There is no site-permission model on iOS today:

- The only WKUIDelegate permission hook is `iOS/DuckDuckGo/TabViewController.swift:3938` — for ordinary sites it returns `.prompt` (WebKit shows its own per-page system-style alert; nothing is persisted), and for Duck.ai it grants/denies microphone based on `AVCaptureDevice.authorizationStatus`. A second, independent handler lives in `SharedPackages/AIChat/Sources/AIChat/iOS/AIChatWebViewController.swift:267` and **defaults to `.deny`** for ordinary requests. These two call sites intentionally differ; both matrices are shipped behavior.
- There is zero iOS geolocation code — no `CLLocationManager`, no `navigator.geolocation` shim; `NSLocationWhenInUseUsageDescription` exists in `iOS/DuckDuckGo/Info.plist` only so WebKit can trigger the OS prompt itself.
- Privacy Dashboard permission hooks are stubbed out on iOS (`iOS/DuckDuckGo/PrivacyDashboard/PrivacyDashboardViewController.swift:278-286`).

**macOS shipped the full model** (Permission Center, Dec 2025) under `macOS/DuckDuckGo/Permissions/` — `PermissionType`, `PersistedPermissionDecision`, `PermissionManager`, Core Data `PermissionStore`, per-tab `PermissionModel`, SwiftUI popovers. It is a useful *reference implementation*, but it is coupled throughout to AppKit/WebKit adapters, Core Data identity (`NSManagedObjectID` in the protocol surface), macOS-only types (`FireproofDomains`), and macOS `.ask`-marker semantics. Review confirmed that only the type identity and decision enums are directly portable — extracting the rest is an API redesign, not a move.

Branch `bartosz/on-site-permissions` is currently identical to `main`; no groundwork has landed.

## 2. Guiding decisions

### D1 — iOS-standalone: no macOS changes, no shared-package extraction in v1

v1 defines its own small model inside the iOS package: a permission type enum (camera / microphone / location only), a tri-state decision (`ask` / `allow` / `deny`), and a per-site value record — roughly 100–250 LOC duplicated instead of a cross-platform extraction.

Rationale (from the independent review, accepted): the extraction would have reused little — the macOS domain layer leaks Core Data identity, exports `FireproofDomains`/`TLD`, carries a `PermissionDecisionOverriding` seam, and even has write semantics worth preserving bug-for-bug (the decision publisher fires from a `defer` even when the store add failed) — while putting shipped, unflagged macOS behavior at risk before iOS ships anything. Convergence is deferred until there is demonstrated reusable behavior; to keep that door open, the persisted type raw values stay byte-identical to macOS's (`"camera"`, `"microphone"`, `"geolocation"`).

### D2 — Persistence: KeyedStoring (UserDefaults), actor-owned, plist DTO

A single store holding `[site-key: [type: decision]]` via the modern `KeyedStoring` API (`SharedPackages/Persistence/Sources/Persistence/KeyValueStoring.swift`; per-domain-map precedent `iOS/DuckDuckGo/TextZoomStorage.swift`).

- **Wire format:** a stable property-list DTO (dictionary of strings), not direct enum storage — the persisted format outlives the types.
- **Concurrency:** one actor-owned (or MainActor-owned) read-modify-write path; no concurrent mutation of the map.
- **Semantics (decided 2026-08-26):** persist `.allow`/`.deny` from explicit choices; persist an explicit `.ask` **only when the user resets a row in the manager** — such rows stay listed in Settings until removed (desktop parity, per the mobile privacy triage). Merely prompting never writes anything.
- Volume is tiny; no Core Data, no migration burden. No at-rest domain encryption (consistent with fireproofing/text-zoom on iOS) — noted for privacy review.

### D3 — Request interception on iOS

- **Camera/mic:** implement `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` routing in `TabViewController` behind the flag. **Flag off — and for any path the feature doesn't handle — the current decision matrix executes verbatim**, including the Duck.ai microphone branch. `AIChatWebViewController` (embedded Duck.ai web view) is **not touched in v1**: routing a shared-package web view through the iOS package is plumbing without user value; its `.deny` default stays as is.
- **Geolocation:** `navigator.geolocation` user-script shim (hack-phase validated), `.atDocumentStart` in the **page content world**, injected into all frames (precedent for page-world/all-frames: `iOS/Core/FullScreenVideoUserScript.swift:23`). The JS ships in the package via `Bundle.module` + `UserScript.loadJS(_:from:)`.
  **v1 scope (explicit):** Window contexts in the main frame and document iframes only. There is **no WKUserScript injection route into workers/service workers** — worker `navigator.permissions.query` parity is deferred, documented as a known gap. The shim must specify: `permissions.query` returning a `PermissionStatus` with correct `state`/`onchange`/EventTarget behavior; per-frame namespaced callback IDs resolved in the originating frame; `getCurrentPosition` option/timeout/cached-position (`maximumAge`) behavior; `watchPosition` cancellation on navigation and web-content-process replacement. Frame identity comes from `WKScriptMessage.frameInfo.securityOrigin` — never from shim-supplied payloads, and never by touching `WKFrameInfo.request` (known crash risk — see the warning in `iOS/DuckDuckGo/TextSelection/SelectionFrameUserScript.swift:23`).
  **Rollback semantics:** disabling the flag stops registering the shim for new page loads; a page that already loaded the shim keeps it until reload/navigation. Documented as accepted rollback behavior.
- **In-use tracking:** KVO on `WKWebView.cameraCaptureState` / `.microphoneCaptureState` for cam/mic; active `watchPosition`/pending requests for location. Feeds the red "in use" state.

### D4 — System-permission layer

`SystemPermissionService` (`AVCaptureDevice` for camera/mic, `CLLocationManager` for location) with states **notDetermined / authorized / denied / restricted / unavailable** — restricted (MDM/parental controls) and unavailable are surfaced distinctly because System Settings cannot fix them (requirements OQ-15); status is refreshed on app activation (the user may return from Settings). Site-first ordering:

1. Site dialog → user allows → OS `notDetermined`: trigger the OS request; `authorized`: proceed; `denied`: decline the request and surface recovery (reminder dialog / sheet link + "couldn't give access" toast); `restricted`/`unavailable`: decline with the OQ-15 treatment.
2. **Combined camera+microphone:** one WebKit decision spans two site decisions and two OS authorizations. v1 rule: grant only when both site decisions and both OS states allow; any partial denial → deny + recovery affordances. Exact UX pending requirements OQ-2 (needed before the dialog PR).
3. Deep link for recovery: `UIApplication.openSettingsURLString`.
4. When the persistent site "allow" is committed relative to a subsequent OS denial is an open product question (requirements OQ-13) — it decides recovery reachability and must be settled with OQ-5.

### D5 — Per-tab coordination: `SitePermissionsCoordinator`

One per tab (owned by `TabViewController`), holding session state (active grants, allow-once windows, in-use flags, pending query queue). Decision precedence (per requirements FR-3, decided): **global Never (absolute) → stored per-site decision → active allow-once grant → prompt**. Working assumptions pending kick-off: "Allow Once" is valid per (tab, site) until the user leaves the site or the tab closes — the full boundary list is requirements OQ-9; Fire-mode tabs neither read nor write the persistent store (session-only prompting, requirements OQ-10).

### Permission-key contract

The key under which decisions are stored and matched is a **privacy boundary**, defined once:

- Derived **natively** from the **top-level frame's** `WKSecurityOrigin` host (media capture is already scoped to the main-frame URL by WebKit; geolocation requests from document iframes are attributed to the top-level site — matching the macOS model's domain semantics).
- Normalization: drop a leading `www.`, keep the rest of the host verbatim (punycode form for IDN); scheme and port are not part of the key; IP literals/localhost are stored as-is.
- **Never** derived from shim-supplied JavaScript values; JS payloads may carry request IDs only.
- Display domain for UI = the stored key.
- **eTLD+1 is used only at the fireproof comparison boundary** (see D8) via the same `TLD` service fireproofing uses — never as the storage key.

### D6 — Feature flag

New `FeatureFlag` case (e.g. `sitePermissions`) in `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift` with `Config(defaultValue: .disabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.…), supportsLocalOverriding: true)`. Note: `.remoteReleasable` + `defaultValue: .enabled` would be ON for everyone whenever the subfeature is absent from privacy config — keep the default `.disabled` until rollout completes. Registry task in the Apple Feature Flags Registry is required before adding the flag. (`.cursor/rules/feature-flags-addition.mdc` paths are stale — flags live in the local package now.)

### D7 — One iOS local package: `iOS/LocalPackages/SitePermissions`

Modeled on `iOS/LocalPackages/SetDefaultBrowser` (the repo's most recent full-feature-in-a-package precedent), but **one production target + one test target**. No `TestSupport` product and no Core/UI target split until a second consumer exists (review: YAGNI — mocks live in the test target). The target holds the model, store, coordinator, system service, geolocation provider + shim JS (`Bundle.module`), the dialog/sheet SwiftUI, and its own `UserText` with `defaultLocalization: "en"` (the Smartling pipeline is package-aware — SetDefaultBrowserUI/SyncUI-iOS already receive 26-locale translations into package resources).

Dependencies: `Persistence`, `BrowserServicesKit` (UserScript), `DesignResourcesKit`/`DesignResourcesKitIcons`, `DuckUI`/`UIComponents` as needed — all proven package dependencies.

**Why a package:** the iOS project has zero buildable folders, so every app-target file costs 4 pbxproj entries — the dominant merge-conflict source on a stacked-PR train. Registering a package is a one-time ~13-line pbxproj edit + a scheme edit (reference commit `0d63fbb8f3`, AppRouting), after which every file in it is pbxproj-free. Package SwiftUI previews, own `.xcassets`, DesignResourcesKit colors, and `AVCaptureDevice` calls all work in packages (SyncUI-iOS proves each).

**Stays app-side (thin glue):** the WKUIDelegate methods and user-script registration (`iOS/DuckDuckGo/UserScripts.swift`, `TabViewController`), menu row builders, the Settings entry **and the settings screens themselves** (in-stack settings pages need app-only `SettingsViewModel`/`SettingsCell`), the `FireExecutor` worker, the `FeatureFlag.sitePermissions` check (by convention no package imports FeatureFlags-iOS; the app checks the flag and wires the package), and pixel definitions (the package emits a typed event enum; the app maps it via `EventMapping` and owns the JSON5 — the `pixels.mdc` pattern, exactly as SetDefaultBrowser does).

**Seams (kept minimal):** the event enum → `EventMapping` boundary; a small system-clients protocol for tests (AV/CoreLocation wrappers); sheet/dialog actions surfaced as closures so the app presents toasts (`ActionMessageView` is app-only). The store is a concrete actor-owned type — no store protocol.

**Discipline (both failure modes already exist in the repo):** add the package's `TestableReference` to `iOS Browser.xcscheme` in the scaffold PR — two existing packages' tests silently never run in CI because this was skipped; and keep `.package(path:)` references real (verify with `swift build`/`swift test` from the package directory) — two packages carry stale paths that only resolve because the workspace masks them.

### D8 — Fire integration

`PermissionsFireWorker` registered in `iOS/DuckDuckGo/Fire/FireExecutor.swift:206-224`:

- `burnNormalModeData()` clears all stored permissions **except** sites whose key, normalized to eTLD+1 through the same `TLD` service fireproofing uses, matches a fireproofed domain (`iOS/Core/Fireproofing.swift` stores eTLD+1 — a literal host comparison would wrongly burn `sub.example.com` while `example.com` is fireproofed).
- `burnFireModeData()` is an **explicit no-op** — there is one store and Fire runs normal- and fire-mode methods concurrently for `.all` (`iOS/DuckDuckGo/Fire/FireWorkers/FireExecutorWorker.swift:28`); a naive TextZoom copy would double-burn. All mutations serialize through the store actor.
- `burnTabData(tabViewModel:domains:)` clears the given domains with the same fireproof exemption.
- Settings "Remove Permissions"/"Remove All" bypass the fireproof exemption (per requirements FR-8).
- **The worker burns stored data even while the feature flag is off** — after a rollback, previously stored permissions must not survive a Fire operation (requirements FR-8).
- Wide-event instrumentation like the other workers; auto-clear comes free via `FireRequest`.

## 3. Component map

| # | Component | Where | Notes |
|---|---|---|---|
| 1 | Permission model (type, decision, per-site record) | `SitePermissions` package | iOS-standalone (D1); raw values byte-identical to macOS for future convergence |
| 2 | `SitePermissionsStore` | package | actor-owned concrete type over `KeyedStoring`, plist DTO (D2); no protocol |
| 3 | `SitePermissionsCoordinator` | package; one per tab, owned by `TabViewController` | D5; no app-type references (closure seams) |
| 4 | Geolocation shim + `GeolocationProvider` | package (JS in `Bundle.module`); registration app-side in `iOS/DuckDuckGo/UserScripts.swift` + per-tab wiring `TabViewController.swift:4187` | D3 scope; page content world, `.atDocumentStart`, all frames; package-defined app-registered precedent: `SharedPackages/EventHub` `WebEventsHandler` (`UserScripts.swift:178-182`) |
| 5 | `SystemPermissionService` | package | D4 (incl. restricted/unavailable, refresh on activation); `AVCaptureDevice` in packages proven (`SyncUI-iOS` `ScanOrPasteCodeViewModel.swift:110`); usage-description keys stay in `iOS/DuckDuckGo/Info.plist` |
| 6 | Site permission dialogs + reminder dialogs | package; presented modally over the tab by app-side glue | 3-option dialog (4 variants incl. DDG SERP) + denied-system reminder dialogs; presentation gating analogous to `WebJSAlert` (`TabViewController.swift:535` `canDisplayJavaScriptAlert`, `iOS/DuckDuckGo/JSAlertView.swift`) so prompts queue and never stack |
| 7 | Menu entry | app target — **both** menus: legacy `iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift` (`buildLinkEntries`, conditional-entry idiom = `buildKeepSignInEntry` returning `nil`) and sheet menu `iOS/DuckDuckGo/BrowsingMenu/SheetPresentationMenu/BrowsingMenuBuilding.swift` + `BrowsingMenuBuilder.swift` | row visible only when the coordinator reports permanent/active state; note the sheet menu's hard-coded seventh-item preferred detent (`BrowsingMenuBuilder.swift:220`) — adding a row shifts it; update the detent logic and its test |
| 8 | Per-site bottom sheet | package (view + view model) | three states (permissions / +reminder / reminder-only); reload caption; Remove Permissions; actions surface as closures — the app presents toasts (`ActionMessageView` with Undo is app-only) |
| 9 | Settings pages | app target: entry in `iOS/DuckDuckGo/SettingsMainSettingsView.swift` + new `SettingsSitePermissionsView` (+ per-site view) | Main Settings entries are **locale-sorted** with `build:` closures returning nil (= hidden) — return nil when the flag is off; page layout follows `SettingsAutoplayView` (`ListBasedPicker`, `.applySettingsListModifiers`); **no deep-link enum work** (YAGNI — no external route required); backed by package store APIs |
| 10 | `PermissionsFireWorker` | app target: `iOS/DuckDuckGo/Fire/FireWorkers/` | thin; D8 semantics (no-op fire-mode, eTLD+1 fireproof comparison, burns with flag off) |
| 11 | Grant animation | package, code-built (no Lottie) | per prototype; placement per requirements OQ-6 |
| 12 | Pixels | typed event enum in the package; app-side `EventMapping` + PixelKit event + `iOS/PixelDefinitions/pixels/definitions/site_permissions.json5` | SetDefaultBrowser pattern (`DefaultBrowserPromptEvent` → app `EventMapping`); mirror macOS naming (`permission_authorization_<type>_<decision>`, `permission_center_changed_…`) minus the `m_mac_` prefix so ClickHouse comparisons work; **never include domains**; validate with `npm run validate-pixel-defs` |
| 13 | Strings & icons | package `UserText` (+ `defaultLocalization: "en"`); app-side glue strings in `iOS/DuckDuckGo/UserText.swift`; new DRK icons | several required glyphs exist only at macOS sizes (16px) — add 24px variants via the `ddg-drk-add-icon` skill |

pbxproj cost: registering the package is a one-time ~13-line pbxproj + scheme edit; after that, package files need no pbxproj entries. Only the app-side glue files (menu rows, settings views, fire worker, pixel mapping) still need the four-place pattern (see `SettingsAutoplayView.swift`, per `.cursor/rules/project-structure.mdc`).

## 4. Key flows (condensed)

- **First request (no stored state):** page → WKUIDelegate/geo-shim → coordinator → global default check (global Never = silent decline, absolute) → 3-option dialog → on allow: `SystemPermissionService` gate (skip if authorized; OS prompt if notDetermined; recovery if denied; OQ-15 treatment if restricted/unavailable) → decision to WebKit/shim → persist iff "Allow While Using Site"/"Never Allow" → animation on grant → menu entry becomes visible.
- **Stored allow + OS denied:** decline, toast ("couldn't give access"), sheet shows reminder state with `Go to System Settings`.
- **Manager change while page is loaded:** store write → sheet shows reload caption → decision applies on next request/reload.
- **Fire:** `forgetAllWithAnimation` → `FireExecutor` → `PermissionsFireWorker` (D8).

## 5. Delivery plan — one Asana subtask per PR (stacked)

One Asana subtask per PR. Target ~1–2k LOC per PR; use `gh stack` so each PR reviews against its parent. Day estimates assume one engineer familiar with the codebase, tests included; total ≈ **17.5 person-days**.

**Decision gates:** OQ-8 is resolved (global Never absolute). Combined camera+mic (OQ-2) and final prompt copy (OQ-4) must be settled **before PR 3**; OQ-5/OQ-13 (commit timing / menu reachability) before PR 3's recovery pieces; OQ-9 (allow-once boundaries) before PR 2 lands its coordinator tests.

| PR / subtask | Contents | Depends on | ~LOC | ~Days |
|---|---|---|---|---|
| **1. Add `sitePermissions` feature flag and permission icon assets** | Flag case + `iOSBrowserConfigSubfeature` + local override (Feature Flags Registry task first); missing 24px DRK glyph variants (via `ddg-drk-add-icon`) | — | ~300 | 0.5 |
| **2. iOS core (no UI): `SitePermissions` package — model, store, system service, decision engine** | Package scaffold (single target + tests; one-time pbxproj + scheme `TestableReference`), standalone model, actor-owned `SitePermissionsStore` (plist DTO), global-defaults storage, `SystemPermissionService` (incl. restricted/unavailable + activation refresh), `SitePermissionsCoordinator` precedence + allow-once windows + query queue; unit tests | 1 | ~1.5–2k | 3 |
| **3. iOS: 3-option dialogs, camera/mic routing, denied-system recovery dialogs** | Dialog UI (camera/mic variants) + presentation queueing; `TabViewController` WKUIDelegate routing behind the flag (legacy matrix verbatim when off; Duck.ai branch preserved; `AIChatWebViewController` untouched); site-first ordering; combined cam+mic rule; in-use KVO; reminder dialogs + "couldn't give access" toasts; package strings | 2 | ~1.8k | 3.5 |
| **4. iOS: geolocation interception and location dialogs** | `navigator.geolocation` + `permissions.query` shim per D3 scope (main frame + document iframes, per-frame IDs, watch cancellation) + native `CLLocationManager` provider + coordinator wiring + location/DDG-SERP dialog variants + privacy-test-pages integration tests | 3 | ~1.5k | 3 |
| **5. iOS: Settings > Site Permissions (global defaults + Manage Sites)** | Locale-sorted Main Settings entry (nil when flag off), global 2-option pickers + absolute silent-decline enforcement, System-Settings footer link, Manage Sites list, per-site page, remove one/all + toasts with Undo | 2 | ~1.5–2k | 2.5 |
| **6. iOS: on-site permission sheet + browser menu entry + reminder states** | Bottom sheet UI/VM (3 states incl. reminder-only, icon states, reload caption, Remove Permissions, `Go to System Settings`) in the package; conditional row in **both** menus + sheet-detent fix + presentation + in-use bindings | 3 | ~1.6k | 3 |
| **7. iOS: Fire Button integration, grant animation, pixels** | `PermissionsFireWorker` per D8; code-built grant animation; pixels end-to-end (package event enum → `EventMapping` → JSON5 definitions → firing sites) | 5, 6 | ~1.2k | 2 |

**Non-PR subtasks** (create alongside, not part of the stack):

- Copy & design QA with Sveta/David — resolves requirements OQ-2/3/4/5/13/14/15; the OQ-2/OQ-4 subset is needed **before PR 3**.
- Privacy confirmation of the Fire/fireproofing exemption (requirements OQ-7) — before PR 7.
- Apple Feature Flags Registry entry — before PR 1.
- Translations finalization (Smartling cherry-pick) — after the UI PRs.
- Rollout & monitoring — remote-releasable ramp internal → % → 100%, watching prompt-volume and manager-engagement pixels.

### Merge & release safety

Any prefix of the stack is releasable; no guarding beyond the flag is needed, and **no PR touches macOS**.

- Flag off, each WKUIDelegate call site executes its **current decision matrix verbatim** — the main browser's `.prompt`-for-ordinary-sites *plus* its Duck.ai microphone grant/deny branch (`TabViewController.swift:3938`); `AIChatWebViewController`'s `.deny` default is untouched in v1 entirely. "Blanket `.prompt` when off" would itself be a regression — both matrices are frozen in regression tests before routing changes.
- The geolocation shim is **not registered/injected** when the flag is off (installing an inert shim would be a flag-off behavior change). Disabling the flag takes effect for new page loads; already-loaded pages keep the shim until reload — documented rollback behavior.
- Menu and settings entry builders return nil when off.
- PR 1 defines an unused flag and unused assets; PR 2 is pure additive package code wired to nothing.
- Deliberate exception: `PermissionsFireWorker` burns stored permission data even when the flag is off (privacy-correct after rollback).

## 6. Testing

- Package unit tests: store (DTO round-trip, serialized mutation), coordinator precedence table (incl. global-Never-absolute over stored Always), allow-once boundaries per OQ-9's resolved definition, system-service state mapping incl. restricted/unavailable.
- Package test target added as a `TestableReference` to `iOS Browser.xcscheme` (CI runs exactly that scheme — no test plans); verify with `swift test` from the package directory too, which also catches stale `.package(path:)` references.
- **Regression tests frozen before any routing change:** the full current decision matrices of both WKUIDelegate call sites (ordinary site / Duck.ai origin × mic / camera+mic × AV status), Voice Search mic flow, SERP "Clear location" behavior.
- View-model/semantic tests for dialogs and sheet states; snapshot tests are optional locally only — CI disables snapshot assertions (`SKIP_SNAPSHOT_TESTS=1` in `iOS Browser.xcscheme`; see `SharedPackages/SnapshotTestingSupport/README.md`).
- Sheet-menu detent test updated with the new row count.
- Fire worker tests: fireproof exemption via eTLD+1 normalization (subdomain case), fire-mode no-op, burn-while-flag-off.
- Geolocation shim: integration tests against the privacy-test-pages fixtures (already added), incl. iframe attribution and `permissions.query` state transitions.
- Accessibility checks: non-color in-use affordance (per OQ-14 once resolved), VoiceOver labels on dialogs/pickers.

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Geolocation shim web-compat (feature detection, `permissions.query`, iframes) | v1 scope pinned in D3 (main frame + document iframes; workers deferred as a documented gap); full API-surface spec incl. `PermissionStatus` semantics; fixtures in privacy-test-pages; flag allows disable (effective on reload) |
| Owning `.grant/.deny` makes us responsible for OS-permission edge cases WebKit handled | `SystemPermissionService` centralizes it with explicit denied/restricted/unavailable states and activation refresh; UI tests for the two-step flow |
| Flag-off regressions at the two shipped WKUIDelegate matrices | matrices frozen in regression tests before PR 3; AIChat call site untouched in v1 |
| Permission-key mistakes create a privacy hole (iframe attribution, JS-supplied hosts) | single key contract (D5), key always derived natively from the top-level frame's `WKSecurityOrigin`; shim payloads carry request IDs only |
| Fireproofing granularity mismatch (eTLD+1 vs host) silently burns fireproofed subdomain permissions | D8 normalizes every stored key through the same `TLD` service before comparing; unit-tested with subdomain cases |
| Concurrent Fire execution double-burning a single store | `burnFireModeData()` no-op + actor-serialized mutations |
| Two live browsing menus drift | one entry-builder consulted by both; detent logic updated with its test |
| Duplicated model drifts from macOS, complicating future convergence | raw values kept byte-identical; convergence explicitly deferred until reusable behavior is demonstrated (D1) |
| Package tests silently skipped in CI (two existing packages already suffer this) | scheme `TestableReference` added in the scaffold PR (PR 2) and checked in review |
| JS user script shipped from a package has no precedent | mechanism (`Bundle.module` + `UserScript.loadJS(_:from:)`) is proven separately; fall back to keeping the `.js` in `iOS/Core/` if it misbehaves |
| Design TODOs (combined dialog, copy, commit timing — requirements OQ-2/3/4/5/13) block PR 3 | decision gates scheduled before PR 3, not late |

## 8. Out of scope (tech)

Any macOS changes (v1); a shared cross-platform Permissions package (deferred until convergence is justified); permission types beyond camera/mic/location; address-bar indicator; per-session toggles / mid-session mute (`setMicrophoneCaptureState` noted for future); worker/service-worker Permissions API parity (no injection route); routing the embedded AIChat web view through the new model; Privacy Dashboard permission wiring on iOS (stays stubbed, matching Desktop's removal of dashboard permission UI); cross-device sync (privacy-prohibited); porting macOS's private geolocation WebKit API.
