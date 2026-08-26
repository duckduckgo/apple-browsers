# Prompt: independent review of the iOS On-site Permission Manager requirements & tech design

You are an independent senior reviewer of a proposed feature design for the DuckDuckGo apple-browsers monorepo (repo root = your working directory). Your feedback goes to the DRI, who will act on it — be constructive, concrete, and evidence-based. **You have no access to Asana, Figma.** Do not attempt to open any asana.com or figma.com links you encounter; treat `docs/on-site-permission-manager/requirements.md` as the authoritative product requirements (it was compiled from the project's full Asana history and the Figma designs) and `docs/on-site-permission-manager/tech-design.md` as the proposal under review. Everything you need is in those two files and the repo. Verify the design's claims against the codebase, not against the documents' own assertions.

## The proposal you are reviewing (summary)

New iOS feature: per-site camera/microphone/location permissions with a 3-option prompt (Allow Once / Allow While Using Site / Never Allow), site-prompt-before-system-prompt ordering, a per-site manager in the browser menu, Settings pages, denied-system-permission recovery, and Fire Button integration — gated behind a new `sitePermissions` feature flag, delivered as a 10-PR stack. Architecturally it is a two-package split:

1. **Extract the shipped macOS permission domain layer** (`PermissionType`, `PersistedPermissionDecision`, `StoredPermission`, `PermissionManager`, `PermissionStore` protocol — currently app-local under `macOS/DuckDuckGo/Permissions/Model/`) into a new cross-platform `SharedPackages/Permissions`; macOS adopts it behavior-neutrally. So the design **does reuse macOS code — the domain layer — while deliberately not reusing** macOS's per-tab `PermissionModel`, its UI, or its Core Data store on iOS.
2. **Build the iOS-specific layer in a new local package** `iOS/LocalPackages/SitePermissions-iOS` (modeled on `iOS/LocalPackages/SetDefaultBrowser`: Core / UI / TestSupport targets): a `KeyedStoring`-backed store, a per-tab decision coordinator, a system-permission service (AVCaptureDevice/CLLocationManager), a `navigator.geolocation` JS shim + native provider, and the dialog/bottom-sheet SwiftUI. Thin app-target glue: WKUIDelegate methods, user-script registration, menu rows, the settings screens themselves, the FireExecutor worker, the feature-flag check, and pixel definitions via `EventMapping`.

## Your tasks

1. **Ground yourself in the macOS implementation first** (read, don't skim): `macOS/DuckDuckGo/Permissions/` (Model, View, ViewModel), the WKUIDelegate permission methods in `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift`, the burn integration in `macOS/DuckDuckGo/Fire/Model/Fire.swift`, and `macOS/UnitTests/Permissions/`. Form your own view of how coupled each domain type is to AppKit, Core Data, and macOS-only types, and how hard the proposed extraction really is.

2. **Weigh the alternatives seriously** before judging the chosen one, with cost/complexity/risk grounded in code you inspected:
   - A: all iOS code in the app target, no new packages;
   - B: the proposed two-package split (chosen);
   - C: skip the `SharedPackages/Permissions` extraction entirely — a small iOS-standalone model (duplicate the few enums/protocols), macOS untouched;
   - D: extract more of macOS (share `PermissionModel`/`PermissionState` too);
   - E: iOS UI inside `SharedPackages/Permissions` via `#if os(iOS)`.
   For each: what does it cost or save across the 10-PR plan in tech-design §5?

3. **Viability checks — verify in the code**, with file:line evidence:
   - `KeyedStoring`/UserDefaults suitability for the per-domain store (`SharedPackages/Persistence/Sources/Persistence/KeyValueStoring.swift`, precedent `iOS/DuckDuckGo/TextZoomStorage.swift`);
   - the geolocation shim route: `iOS/DuckDuckGo/UserScripts.swift` registration paths, content worlds, `navigator.permissions.query`, iframes/workers, and the precedent of package-defined app-registered scripts (e.g. `SharedPackages/EventHub`, `SharedPackages/SERPSettings`);
   - WKUIDelegate media-capture routing and the flag-off `.prompt` passthrough (`iOS/DuckDuckGo/TabViewController.swift` ~line 3937, plus the second call site `SharedPackages/AIChat/Sources/AIChat/iOS/AIChatWebViewController.swift`);
   - FireExecutor worker fit (`iOS/DuckDuckGo/Fire/FireExecutor.swift`, `TextZoomFireWorker.swift`), fireproofing eTLD+1 normalization (`iOS/Core/Fireproofing.swift`);
   - both browsing menus needing the entry (`iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift`, `iOS/DuckDuckGo/BrowsingMenu/SheetPresentationMenu/`);
   - Settings integration pattern (`iOS/DuckDuckGo/SettingsRootView.swift`, `SettingsAutoplayView.swift`);
   - package test wiring in `iOS/DuckDuckGo-iOS.xcodeproj/xcshareddata/xcschemes/iOS Browser.xcscheme` and localization from packages (`iOS/LocalPackages/SetDefaultBrowser`, `SyncUI-iOS`).

4. **Simplification pass — be aggressive.** Which PRs, components, protocol seams, or package targets can be deleted, merged, or replaced by something already in the repo? Is anything speculative (YAGNI): the TestSupport product, the number of seams, the `.ask`-marker semantics, the extraction itself? Could v1 ship with less?

5. **Release-safety check.** The design claims the app is releasable after any prefix of the PR stack with the flag off (tech-design §5 "Merge & release safety"). Try to falsify it: find any wiring point where flag-off behavior could still change (user-script injection, delegate-method presence, scheme/pbxproj edits, macOS refactor regressions).

6. **Requirements review.** Check `requirements.md` for internal consistency and ambiguities that will bite implementation; check every FR and open question (OQ-1…OQ-12) is either covered by the tech design or explicitly deferred.

## Output format

1. Verdict per area (extraction / iOS package / geolocation shim / persistence / delivery plan / release safety): **viable / viable with changes / not viable**, each with file:line evidence.
2. Top issues, ranked by impact, each with a concrete suggested change.
3. Simplification opportunities, ranked by estimated LOC/PRs saved.
4. Alternatives comparison table (A–E above).
5. Open questions for the DRI.

Do not rewrite the documents or change any code — feedback only.
