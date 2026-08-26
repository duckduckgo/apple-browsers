# [iOS] On-site Permission Manager — High-Level Tech Design

Companion to [requirements.md](requirements.md). This describes *how* we build the feature in the apple-browsers monorepo; the implementation plan (task-by-task) is a separate downstream artifact.

**Asana:** main task https://app.asana.com/1/137249556945/task/1213800892997347
**Revision note:** updated 2026-08-26 after a second independent review (fact-check round). Headline changes: Fire integration moved into the first write-capable PR, a 6-PR stack, `@MainActor` store with split storage keys, a corrected permission-key contract (top-level site ≠ requesting frame), corrected flag-off matrices, Duck.ai recorded as an explicit exception, and honest estimates (~21–25 person-days).

Decisions of record (DRI, 2026-08-26): iOS-standalone (no macOS changes); implementation in a local package (synchronized buildable folders were evaluated as a viable, slightly cheaper alternative — the package was chosen for isolation and package-level tests); **per-site decisions override the global Never Allow default** (platform-aligned, reversing an earlier absolute rule); user-reset `.ask` rows stay listed; **Duck.ai is an explicit exception to the whole model**; fire-mode tabs read stored decisions but never write; one feature flag (no geolocation subflag).

**Decision rule for unknowns:** the Asana task and its linked approved artifacts are the source of truth; otherwise follow macOS unless its behavior doesn't make sense on mobile, then Android. Shipped-platform behavior is catalogued with citations in [platform-precedents.md](platform-precedents.md) (reviewed 2026-08-26; it resolved OQ-8/9/10/13/20 and corrected several assumptions below).

---

## 1. Current state (what we build on)

**iOS is greenfield.** There is no site-permission model on iOS today:

- The only WKUIDelegate permission hook is `iOS/DuckDuckGo/TabViewController.swift:3938-3950`: the Duck.ai branch handles **microphone and camera+microphone by checking audio status only** (authorized grants; any other audio state denies; video status is ignored); everything else — **including Duck.ai camera-only** — returns `.prompt`. The second call site, `SharedPackages/AIChat/Sources/AIChat/iOS/AIChatWebViewController.swift:267-279`, has the same audio-only Duck.ai branch but returns `.deny` for every non-matching request, camera-only included. These exact matrices are shipped behavior and must be frozen in regression tests (including camera-only and audio-authorized/video-denied combined cases) before any routing change.
- There is zero iOS geolocation code — no `CLLocationManager`, no `navigator.geolocation` shim; only the usage descriptions in `iOS/DuckDuckGo/Info.plist:169-176`. Privacy Dashboard permission callbacks are stubs (`iOS/DuckDuckGo/PrivacyDashboard/PrivacyDashboardViewController.swift:278-286`).
- Deployment floor is iOS 15; `requestMediaCapturePermissionFor` and the KVO-compliant `cameraCaptureState`/`microphoneCaptureState` are all iOS 15 APIs — no availability fallbacks needed.

**macOS shipped the full model** (Permission Center, Dec 2025) under `macOS/DuckDuckGo/Permissions/`. It is a reference implementation only: Core Data identity, `FireproofDomains`/`TLD`, and override seams leak through its protocols, and only the type/decision enums are directly portable (verified twice). v1 does not touch it.

Housekeeping: the branch `bartosz/on-site-permissions` is one docs-only commit ahead of `main` and ~31 commits behind — **rebase before implementation starts**.

## 2. Guiding decisions

### D1 — iOS-standalone: no macOS changes, no shared-package extraction in v1

v1 defines its own small model: a permission type enum (camera / microphone / location), a tri-state decision (`ask` / `allow` / `deny`), and a per-site record — ~100–250 LOC duplicated instead of a cross-platform extraction. Persisted raw values stay byte-identical to macOS's (`"camera"`, `"microphone"`, `"geolocation"`) to keep future convergence cheap. Do **not** reuse BSK's dashboard DTOs (`AllowedPermission`, `PermissionAuthorizationState` — presentation types with `.grant` vocabulary) or `DomainsProtectionStore` (a boolean set; cannot express tri-state per-type).

### D2 — Persistence: `@MainActor` store over KeyedStoring, split keys

A concrete **`@MainActor final class SitePermissionsStore`** (no actor: every consumer — Fire workers, WK delegates, Settings, menus, SwiftUI — is already main-actor, and `KeyedStoring` is synchronous; an actor would add `await`/Sendable ceremony for nothing). No store protocol.

- **Two storage keys:** the per-site map and the global defaults are stored separately, so Fire / "Remove All" can clear sites while **preserving global defaults**.
- **Wire format:** the nested `[String: [String: String]]` map stored directly as a property list (`KeyValueStoring.swift:329-332` stores plist collections natively; a Codable struct would become opaque JSON `Data`). No versioned DTO. Avoid dotted storage keys (they assert in `KeyedStoring`).
- **Semantics (decided):** persist `.allow`/`.deny` from explicit choices; persist an explicit `.ask` **only when the user resets a row in the manager**. The sparse map is the whole mechanism — no entry = never chosen; `"ask"` entry = user-reset, still listed; Remove Permissions deletes the record; **Undo restores exactly the deleted record, only if the site still has no newer record, and never restores ephemeral grants**. No tombstones, marker sets, or second list.
- Merely prompting never writes anything. No at-rest encryption (consistent with fireproofing/text-zoom) — noted for privacy review.

### D3 — Request interception on iOS

- **Camera/mic:** route `webView(_:requestMediaCapturePermissionFor:...)` in `TabViewController` behind the flag. **Duck.ai is an explicit exception in both flag states** (decided): both call sites keep their current branches verbatim; the 3-option prompt, stored decisions, and global Never Allow do not apply to duck.ai origins. Flag off, the full current matrices run verbatim. `AIChatWebViewController` is untouched entirely.
- **Geolocation:** a dedicated app-registered `UserScript` (JS in the package via `Bundle.module` + `UserScript.loadJS(_:from:)` — mechanism verified, though this is its first production use), `.atDocumentStart`, page content world, all frames (precedent: `iOS/Core/FullScreenVideoUserScript.swift:35-38`). **Not** built on content-scope-scripts for v1: the pinned C-S-S build has no Apple geolocation feature (an external-repo change/release), and its push API evaluates without an originating frame.
  - **Message plumbing:** use `WKScriptMessageHandlerWithReply` for one-shot calls (`getCurrentPosition`, `permissions.query`) — registration/forwarding already exists in `UserContentController.swift:297-313`; request IDs only for long-lived `watchPosition`/`clearWatch`; wrap repeated watch callbacks with the safe frame pattern from `iOS/DuckDuckGo/TextSelection/SelectionFrameUserScript.swift:23-42` (never touch `WKFrameInfo.request`).
  - **v1 scope:** Window contexts in the main frame and document iframes. No worker/service-worker injection route exists — worker parity is a documented gap. Platform gating is preserved: a stored allow never authorizes an insecure context, a sandboxed frame, or an iframe not delegated by Permissions Policy.
  - **`permissions.query`:** answered immediately from current state (never queued); PR 6 delivers an authoritative `PermissionStatus.state`/`change` transition table covering global Never, stored allow/deny/ask, active allow-once, all OS states, and policy denial. Two Android bridge defects not to copy: its Permissions API returns denied for geolocation entirely, and its query checks existing grants before allowed-to-ask, so query and the next real request can disagree — iOS `query` must apply the same precedence as real requests.
  - **Lifecycle:** watches cancel on navigation and web-content-process replacement. The shim must not depend on user-script installation order (assembly order is nondeterministic, `UserScripts.swift:219-233`).
  - **Rollback:** flag off → shim not registered for new loads; already-loaded pages keep it until reload. This path is **not free**: `UserScripts.userScripts` is lazy and `ContentBlockingUpdating` does not subscribe to flag updates — test ON→OFF→new-navigation explicitly, and test handler-vs-script lifetime (WebKit removes scripts on asset changes but retains handlers).
  - **Fixtures:** verified present in the privacy-test-pages repo (local checkout inspected 2026-08-26): `features/geolocation.html`, `features/permissions-api.html`, `features/iframe-permissions.html`, `features/iframe-media-prompt*.html`. PR 5/6 **extend** them; known gaps to add: a minimal combined camera+mic page, an Allow Once reload/navigation/tab-close matrix, OS-denied recovery, and a manager-originated mutation while a `PermissionStatus` change listener is attached.
- **In-use tracking:** KVO on `cameraCaptureState`/`microphoneCaptureState`; active watches/pending requests for location. `.muted` presentation is OQ-19.

### D4 — System-permission layer

One small injected **system client** (not a service layer): AV status/request plus a **single shared `CLLocationManager` driver used for both authorization and position delivery** (two managers could observe divergent state). States: notDetermined / authorized / denied / **restricted / unavailable** (System Settings cannot fix the last two — OQ-15 UX); refresh on app activation. Site-first ordering as before. **Combined camera+microphone:** one WebKit decision spans two site and two OS decisions — grant only when all allow; any partial denial → deny + recovery (both platforms confirm one combined dialog; copy pending OQ-2, gates PR 3). Evaluate each OS permission separately when classifying a combined denial — Android checks only the first and misclassifies camera-only permanent denials; do not copy that. Recovery deep link: `UIApplication.openSettingsURLString`.

### D5 — Per-tab coordination: one concrete `@MainActor` coordinator

One `SitePermissionsCoordinator` per tab, owned by `TabViewController`. No coordinator protocol, no separate decision engine, no per-permission subcoordinators.

- **Precedence** (per requirements FR-3, platform-aligned): duck.ai exception → stored per-site Never → stored per-site Allow (OS-gated) → active allow-once grant → **global Never (prevents new asking only)** → prompt. An explicit `.ask` entry is **not** a decision at request time — it falls through and affects only Settings listing. A one-time Deny suppresses re-asks for the current page; a completed one-time Allow may prompt again (macOS model). Combined stored state: any deny wins; all-allow grants; partial allow+ask prompts.
- **Own prompt FIFO.** The existing `WebJSAlert` path does not queue — it declines a request when another presentation is active (`TabViewController.swift:3994-4016`; `JSAlertView` holds one alert). Permission prompts get their own small FIFO; only user-facing requests enter it.
- **Navigation generation:** before persisting or delivering any late AV/CoreLocation result, verify tab, top-level key, requesting frame, web-content process, and navigation generation still match.
- **Allow Once (OQ-9 resolved, macOS model):** in-memory and page-scoped — ends on reload, any non-same-document navigation, tab close, web-content-process replacement, and app termination; never persisted or restored (explicitly not Android's 24-hour TTL); same-document/SPA history updates do not end it.
- **Fire-mode tabs (OQ-10 resolved, Android model):** read stored decisions and global defaults, never write; grants made there are memory-only.
- **Mid-session changes (OQ-20 resolved, macOS model):** an explicit per-site deny or Remove Permissions immediately revokes active use — `setCameraCaptureState(.none)` / `setMicrophoneCaptureState(.none)` plus stopping geolocation watch delivery; grants and all other changes apply on reload/next request (the reload caption, requirements OQ-11).

### Permission-key contract

The stored/matched key is a privacy boundary, defined once:

- **Top-level site ≠ requesting frame.** `message.frameInfo.securityOrigin` identifies the *requesting iframe*. The **storage key** derives from the tab's committed main-frame URL (native navigation state); the requesting frame's origin is kept separately for Permissions-Policy/secure-context checks and callback routing. Media capture is already main-frame-scoped by WebKit.
- Normalization: host with leading `www.` dropped, punycode form for IDN; **scheme and port are collapsed** (host-only key, matching the macOS model) — recorded for privacy confirmation (requirements OQ-21); grants only ever apply in secure contexts, which platform gating enforces.
- Never derived from shim-supplied JavaScript values; JS payloads carry request IDs only.
- eTLD+1 is used **only** at the fireproof boundary, via `fireproofing.isAllowed(fireproofDomain:)` — which also preserves the implicit DuckDuckGo/Duck.ai exemptions (`iOS/Core/Fireproofing.swift:85-120`); never compare raw `allowedDomains`.
- **Geolocation from cross-site iframes** (requesting frame and top-level page differ at eTLD+1) is denied outright — Android's shipped guard, adopted. Internal (`duck://`), file, and error pages never store or match permission state (macOS keys file origins to a synthetic `localhost` — do not replicate).

### D6 — Feature flag

One flag: `sitePermissions` in `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift`, `Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.…))` — `.disabled` default and local overriding are already the `Config` defaults; the parent feature kill-switch still applies. **No geolocation subflag** (decided — a staged camera/mic-first release is not planned; the stack still keeps camera/mic coherent internally). Registry task required before PR 1. Flag off preserves today's behavior exactly, per the matrices in §1.

### D7 — One iOS local package: `iOS/LocalPackages/SitePermissions`

**Single production target + one test target** — the shape precedent is `iOS/LocalPackages/AppRouting` (SetDefaultBrowser has Core/UI/TestSupport; we deliberately don't copy that). Holds the model, store, coordinator, system client, geolocation provider + shim JS (`Bundle.module`), dialog/sheet SwiftUI, and `UserText` with `defaultLocalization: "en"` (package localization proven: SetDefaultBrowser and SyncUI-iOS each carry 26 `.lproj`s).

Chosen over app-target synchronized buildable folders (both viable; folders are marginally cheaper — ~14 pbxproj lines, tests ride UnitTests) for isolation and package-level tests — DRI decision.

**Stays app-side (thin glue):** WKUIDelegate methods, user-script registration (`iOS/DuckDuckGo/UserScripts.swift`; per-tab wiring at `TabViewController.swift:4204`), menu row builders, the Settings entry and screens (app-only `SettingsViewModel`/`SettingsCell`), the `FireExecutor` worker, the flag check, and pixel firing: the package emits a typed event enum, the app maps it via `EventMapping` (SetDefaultBrowser pattern — but implement the concrete handler with **PixelKit**, not the legacy `Pixel` its handler uses; `pixels.mdc` requires PixelKit for new code).

**Discipline:** add the package's `TestableReference` to `iOS Browser.xcscheme` in PR 1 (two existing packages' tests silently never run). Verification: the package imports UIKit/WebKit, so host `swift test` builds for macOS and fails — run tests via iOS Simulator `xcodebuild` (the app scheme); use `swift package resolve` only to catch stale `.package(path:)` references (two packages already carry masked stale paths).

### D8 — Fire integration (lands in PR 1, before anything can persist)

`PermissionsFireWorker` registered in `iOS/DuckDuckGo/Fire/FireExecutor.swift:206-224`, shipped **with the store** — otherwise "any prefix is releasable" fails the moment the flag turns on and choices persist without a burn path.

- `burnNormalModeData()` clears the **per-site map only** (global defaults preserved), excluding sites where `fireproofing.isAllowed(fireproofDomain:)` matches after eTLD+1 normalization through the same `TLD` service.
- `burnFireModeData()` is an explicit no-op (single store; `.all` runs both methods via `async let` when fire mode is enabled — `FireExecutorWorker.swift:28-52`; everything is `@MainActor`, so the MainActor store serializes naturally).
- `burnTabData` clears the given domains with the same exemption. Settings "Remove Permissions"/"Remove All" bypass the fireproof exemption but also preserve global defaults.
- The worker burns stored data **even while the flag is off** (rollback must not strand data).
- Wide-event instrumentation like the other workers; auto-clear comes free via `FireRequest`.

## 3. Component map

| # | Component | Where | Notes |
|---|---|---|---|
| 1 | Permission model (type, decision, per-site record) | `SitePermissions` package | D1; raw values byte-identical to macOS |
| 2 | `SitePermissionsStore` | package | `@MainActor` concrete class over `KeyedStoring`; split keys; sparse-map `.ask`; snapshot-Undo (D2) |
| 3 | `SitePermissionsCoordinator` | package; one per tab, owned by `TabViewController` | D5; own prompt FIFO; navigation-generation checks; no app-type references |
| 4 | Geolocation shim + provider | package (JS via `Bundle.module`); registration app-side (`UserScripts.swift`, per-tab wiring `TabViewController.swift:4204`) | D3; reply-handler one-shots, IDs for watches, safe frame wrapper; order-independent |
| 5 | System client | package | D4; one seam; shared `CLLocationManager` driver for auth + positions |
| 6 | Site permission dialogs + reminder dialogs | package; presented by app-side glue | 3-option dialog (4 variants incl. DDG SERP) + denied-system reminder dialogs; presented through the coordinator's own FIFO — the `WebJSAlert` path declines concurrent alerts rather than queueing, so it is not reusable for this |
| 7 | Menu entry | app target — both menus (`TabViewControllerMenuBuilderExtension.swift` `buildLinkEntries`; sheet menu `BrowsingMenuBuilding.swift` + `BrowsingMenuBuilder.swift`) | visibility default per requirements FR-4/OQ-17; the sheet's preferred detent is hard-coded to item 7 (`BrowsingMenuBuilder.swift:220-228`) — make it dynamic (`base + visible permission row`), and add present/absent tests (none exist today) |
| 8 | Per-site bottom sheet | package (view + view model) | three states; reload caption; Remove Permissions; actions surface as closures — the app presents toasts (`ActionMessageView` is app-only) |
| 9 | Settings pages | app target: locale-sorted entry in `SettingsMainSettingsView.swift` (nil `build:` closure when flag off) + new views following `SettingsAutoplayView` (`ListBasedPicker`) | no deep-link work; backed by package store APIs |
| 10 | `PermissionsFireWorker` | app target: `iOS/DuckDuckGo/Fire/FireWorkers/` | D8; ships in PR 1 |
| 11 | Grant animation | package, code-built (no Lottie) | ships with the camera/mic flow (PR 3); placement per requirements OQ-6 |
| 12 | Pixels | event enum in package; app-side `EventMapping` → **PixelKit** event + `iOS/PixelDefinitions/pixels/definitions/site_permissions.json5` | mirror macOS naming minus `m_mac_`; never include domains; `npm run validate-pixel-defs` |
| 13 | Strings & icons | package `UserText`; app glue strings in `iOS/DuckDuckGo/UserText.swift`; icons | 24px permission glyphs (outline/solid/blocked) **already exist** in DesignResourcesKitIcons — only `Website-Permissions-Color-24` and possibly some convenience accessors are genuinely new |

## 4. Key flows (condensed)

- **First request:** page → WKUIDelegate/shim → coordinator → duck.ai exception check → stored decision → active grant → global default (Never Allow silently declines new asks) → 3-option dialog → on allow: system client gate (skip if authorized; OS prompt if notDetermined; **if OS already denied → Case B reminder dialog** with `Change Permissions`/`Cancel`; restricted/unavailable → OQ-15 treatment) → decision to WebKit/shim → persist iff Allow While Using Site / Never Allow → grant animation → menu entry visible.
- **Fresh OS denial at the prompt (Case A):** decline + "couldn't give access" toast; sheet gains the reminder state.
- **Stored allow, OS already denied:** decline + toast; sheet reminder state; next explicit site allow → Case B reminder dialog.
- **Manager change while the page holds a permission:** grants and other changes → store write → reload caption → apply on next request/reload; an **explicit deny or Remove Permissions revokes active use immediately** (capture-state APIs; geolocation watches stopped).
- **Fire:** `FireExecutor` → `PermissionsFireWorker` (D8) — per-site map only, fireproof-exempt, globals preserved.

## 5. Delivery plan — one Asana subtask per PR (stacked)

One Asana subtask per PR; `gh stack`; rebase the branch on `main` first (it is ~31 commits behind). Total ≈ **21–25 person-days** (second review re-estimated 22–26; the accepted simplifications recover ~1–2). PRs 1–4 form a coherent camera/mic milestone internally; everything ships behind the single flag.

**Decision gates:** OQ-7 (privacy: fireproofing + globals-preserved clearing) **before PR 1**; OQ-2 (combined dialog copy) + OQ-4 (copy) + OQ-1/3/15 (recovery copy/states) + OQ-6 (animation) + OQ-14/19 (in-use affordance, `.muted`) + OQ-16 (friction pixel) **before PR 3**; OQ-12 + OQ-17/18 (Settings header, menu membership, sheet rows) **before PR 4**. OQ-8/9/10/13/20 are **resolved** (platform-precedents review, 2026-08-26) — PR 2's coordinator tests encode them; ratify at kickoff.

| PR / subtask | Contents | Depends on | ~LOC | ~Days |
|---|---|---|---|---|
| **1. Foundations: flag, assets, `SitePermissions` package — model, store, global defaults, Fire worker** | Registry task then flag; `Website-Permissions-Color-24` + missing accessors; package scaffold (pbxproj + scheme `TestableReference`); model; `@MainActor` store (split keys, sparse `.ask`, snapshot-Undo); ungated `PermissionsFireWorker` (D8) + tests | — | ~1.5k | 3 |
| **2. Coordinator + system client** | Concrete `@MainActor` coordinator (precedence incl. duck.ai exemption, allow-once windows, prompt FIFO, navigation generation); system client (AV + shared CLLocationManager driver, restricted/unavailable, activation refresh); tests incl. frozen legacy matrices of both call sites (camera-only and audio-auth/video-denied cases) | 1 | ~1.5k | 2.5 |
| **3. Camera/mic flow: dialogs, routing, recovery, animation, flow pixels** | 3-option dialog (cam/mic + combined rule) + FIFO presentation; `TabViewController` routing behind the flag (legacy matrix verbatim when off; Duck.ai branch preserved; AIChat untouched); Case A toast + Case B reminder dialog; in-use KVO; grant animation; prompt/decision pixels | 2 | ~1.8k | 4.5 |
| **4. Management surfaces: Settings, sheet, menus** | Locale-sorted Settings entry + global pickers + prevent-asking enforcement (per-site overrides preserved) + Manage Sites + per-site page; on-site sheet (3 states); both menu entries + dynamic detent + present/absent tests; remove one/all + Undo (snapshot semantics) + toasts; **immediate revocation on deny/remove**; management pixels | 3 | ~2k | 4.5 |
| **5. Geolocation: shim, provider, dialogs** | Shim per D3 (reply handlers, watches, frame routing, secure-context/Permissions-Policy gating, cross-site-iframe guard) + provider + coordinator wiring + location/DDG-SERP dialogs; **extend** the existing privacy-test-pages fixtures with the missing combined/lifecycle/recovery cases | 3 | ~1.8k | 4 |
| **6. Geolocation management + hardening** | Sheet/Settings states for location; `PermissionStatus` transition table + `change` events; geo pixels; rollback tests (ON→OFF→navigation, handler lifetime); integration hardening | 4, 5 | ~1.2k | 3.5 |

**Non-PR subtasks:** copy & design QA with Sveta/David (OQ-2/3/4/5/6/13/14/15/17/18/19 — the OQ-2/4 subset before PR 3); privacy confirmation (OQ-7 + host-key OQ-21) before PR 1; Feature Flags Registry entry before PR 1; translations finalization after the UI PRs; rollout & monitoring.

### Merge & release safety

Any prefix of the stack is releasable, with the flag on or off:

- Fire ships **with** the store (PR 1), so persisted state always has a burn path — including after a rollback (the worker runs with the flag off, deliberately).
- Flag off, both WKUIDelegate call sites run their **current matrices verbatim** (per §1, camera-only cases included); regression tests freeze them in PR 2 before PR 3 touches routing. Duck.ai behavior is identical in both flag states (explicit exception).
- The shim is not registered when the flag is off; already-loaded pages keep it until reload (documented). The ON→OFF path is explicitly tested (lazy `userScripts`, no automatic flag subscription in `ContentBlockingUpdating`, handler-vs-script lifetime).
- Menu/settings builders return nil when off; the detent stays correct in both states via the dynamic index.

## 6. Testing

- Package tests via the app scheme on an iOS simulator (`TestableReference` added in PR 1; host `swift test` cannot build an iOS-only package). `swift package resolve` guards stale paths.
- Store: plist round-trip, split-key isolation (Fire preserves globals), sparse `.ask`, Undo snapshot semantics (no restore over a newer record; never ephemeral grants).
- Coordinator: precedence table (stored Allow keeps working under global Never; global Never blocks new prompts; duck.ai exemption; explicit-ask fall-through; page-scoped one-time Deny suppression; combined deny-wins/all-allow/partial matrices), the full Allow Once lifecycle matrix (reload, same-document navigation, cross-site navigation, tab close, process death, app termination, restored tabs — no grant survives), FIFO, navigation-generation rejection of late callbacks.
- Fire-mode tabs: stored decisions and globals are read, nothing is ever written; grants are memory-only.
- Immediate revocation: deny/Remove during active capture stops camera/mic (capture-state APIs) and geolocation watches; grants require reload/next request.
- **Legacy matrices frozen:** both call sites × {ordinary site, duck.ai} × {mic, camera-only, camera+mic} × AV states, including audio-authorized/video-denied; Voice Search mic flow; SERP "Clear location".
- Fire worker: fireproof exemption via `isAllowed(fireproofDomain:)` (subdomain + implicit-domain cases), fire-mode no-op, burn-while-flag-off, globals preserved.
- Geolocation: extend the existing privacy-test-pages fixtures; iframe attribution incl. the cross-site eTLD+1 guard (same-origin, same-site, cross-site requesters), secure-context/Permissions-Policy gating, `permissions.query` transitions (query must agree with the next real request), watch cancellation on navigation/process swap, ON→OFF→new-navigation rollback, handler lifetime.
- Menus: entry present/absent per flag/state; dynamic detent in both layouts (no detent test exists today — add them).
- **No snapshot tests in v1**: `SKIP_SNAPSHOT_TESTS=1` makes image assertions silently pass locally *and* in CI — semantic/view-model tests instead.
- Accessibility: non-color in-use affordance (per OQ-14), VoiceOver labels on dialogs/pickers.

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Geolocation shim web-compat (feature detection, `permissions.query`, iframes, Permissions Policy) | D3 scope pinned; platform gating preserved; transition table in PR 6; fixtures verified/authored in PR 5; flag disable effective on reload |
| Shim rollback not actually reaching loaded/lazy state | explicit ON→OFF→navigation and handler-lifetime tests (PR 6) |
| Flag-off regressions at the two shipped call-site matrices | matrices frozen in PR 2, camera-only cases included; AIChat untouched; Duck.ai exception identical in both states |
| Permission-key mistakes (top-level vs requesting frame, JS-supplied hosts, scheme/port collapse) | key contract: top-level from native navigation state, requesting frame kept separately, IDs-only JS payloads; host-only key sent to privacy (OQ-21) |
| Persisted data without a burn path in a partial rollout | Fire worker ships in PR 1, runs flag-off |
| Fireproofing granularity/implicit exemptions | `isAllowed(fireproofDomain:)` only; subdomain unit tests |
| Two menus + hard-coded detent drift | one entry-builder consulted by both; dynamic detent + new tests |
| Estimate pressure (second review: 22–26d raw) | 21–25d planned; PR 5/6 split keeps the riskiest work isolated at the tail; camera/mic milestone coherent by PR 4 |
| Duplicated model drifts from macOS | identical raw values; convergence deferred deliberately (D1) |
| Package tests silently skipped / stale paths | scheme `TestableReference` in PR 1; `swift package resolve` check |
| `Bundle.module` user-script JS has no production precedent | mechanism verified in BSK tests; fallback: move the `.js` to `iOS/Core/` |
| Design TODOs block PR 3/4 | decision gates scheduled per §5 |

## 8. Out of scope (tech)

Any macOS changes; a shared cross-platform Permissions package; routing Duck.ai (either call site) through the model — explicit exception in both flag states; a geolocation subflag / staged camera-mic-first public release; permission types beyond camera/mic/location — named explicitly: notifications, pop-ups, autoplay, device motion, **DRM/protected media** (Android's fourth permission), and **screen/display capture**; address-bar indicator; per-session toggles / general mid-session mute (immediate revocation on deny/remove is in scope; live toggles are not); worker/service-worker Permissions API parity; Privacy Dashboard permission wiring; cross-device sync; porting macOS's private geolocation WebKit API.
