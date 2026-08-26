# Platform precedents for the iOS On-site Permission Manager

**Investigation date:** 2026-08-26

**Android checkout (`git log -1 --format='%h %ad %d'`):** `0e81d360fc Sat Aug 22 20:29:16 2026 +0000  (HEAD -> develop, tag: 5.292.1.7-internal, origin/develop, origin/HEAD)`

**Scope:** Read-only inspection of the existing local checkouts. No fetch, pull, code change, Asana access, or Figma access was used. The Android conclusions therefore describe this checkout and its existing local refs, not unknown upstream work.

Citation roots used below:

- `macOS/` is this `apple-browsers` checkout.
- `android/` is `/Users/bkunat/Desktop/ddg-workspace/ddg-android/`.
- `fixtures/` is `/Users/bkunat/Desktop/ddg-workspace/privacy-test-pages/`.

## Headline contradictions

| Area | Platform precedent that differs from the iOS default |
|---|---|
| Global precedence | Android explicitly lets a per-site `ALLOW_ALWAYS` override a disabled global ask control; iOS says global Never Allow is absolute. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:123-150`) |
| Allow Once | macOS re-prompts after a completed one-time media use and resets runtime state on reload/navigation. Android persists a tab+host grant for nominally 24 hours, so leaving and returning to the host does not end it. Neither matches the complete iOS window. (`macOS/UnitTests/Permissions/PermissionModelTests.swift:636-708`; `android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/sitepermissionsallowed/SitePermissionAllowedEntity.kt:22-37`) |
| Site allow followed by OS denial | Android commits an allow only after the Android runtime permission succeeds. When no requested resource was autoaccepted, a remembered site allow followed by permanent OS denial becomes per-site `DENY_ALWAYS`; iOS proposes committing the site allow at choice time so recovery remains reachable. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:506-520,598-624`) |
| List privacy | Both shipped platforms create a persistent row after a temporary allow. This is broader than iOS's explicit-reset-only `.ask` record and its “no passive records” rule. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:204-213`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:189-203`) |
| Storage identity | Both platforms use a requesting origin/frame host in at least one path rather than the top-level committed site. Android also preserves `www.`, whereas iOS proposes a top-level host key with `www.` removed. (`macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift:105-116,143-160`; `android/common/common-utils/src/main/java/com/duckduckgo/common/utils/UriExtension.kt:156,247-255`) |
| Mid-session revocation | macOS shows a reload banner but also immediately revokes active capture after a deny or remove. iOS v1 proposes reload/next-request behavior only. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:229-251,268-305`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:469-483`) |
| Fire-mode isolation | Android suppresses permission writes in Fire mode but still reads shared stored decisions; macOS Burner tabs use the shared persistent manager for both reads and writes. iOS proposes neither reading nor writing per-site state. (`android/app/src/main/java/com/duckduckgo/app/browser/BrowserChromeClient.kt:148-157`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:73-146`; `macOS/DuckDuckGo/Tab/Model/Tab.swift:175-216,336-337`) |

## 1. Global versus per-site precedence (OQ-8)

### macOS findings

The inspected macOS request evaluator has no comparable global Camera/Microphone/Location “Never” control. It resolves the normalized domain's stored decision, then runtime state, and grants or denies from that per-domain result. This is useful for per-site behavior but is not a direct global-precedence precedent. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:391-427`)

The closest macOS analogy is Autoplay: the per-domain decision is evaluated before the global policy, so a site allow can override the global fallback, including global Never. Because Autoplay is a different permission category, this is supporting context rather than a direct Camera/Microphone/Location precedent. (`macOS/DuckDuckGo/Tab/Navigation/AutoplayPolicyTabExtension.swift:111-138`; `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift:24-35`)

### Android findings

The global controls are per-type SharedPreferences booleans, defaulting to enabled. (`android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/SitePermissionsPreferences.kt:32-57`)

Android deliberately computes permission-to-ask as `(global ask enabled || per-site ALLOW_ALWAYS) && per-site != DENY_ALWAYS` for Camera, Microphone, DRM, and Location. A stored per-site allow therefore wins over the global “prevent sites from asking” value. The request pipeline applies this predicate before it checks existing grants or displays a prompt. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:123-150`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:92-96,119-145`; `android/site-permissions/site-permissions-impl/src/test/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepositoryTest.kt:105-120`)

### Recommendation for iOS

Keep the documented absolute global Never Allow rule, but ratify it as an intentional cross-platform difference and add an explicit regression test for stored Allow + global Never. This **contradicts** the iOS default in `requirements.md`/`tech-design.md`.

**Verdict:** `contradicts iOS default`

## 2. “Allow Once” validity window (OQ-9)

### macOS findings

A non-remembered macOS result grants the current authorization query and persists an `.ask` marker only for Permission Center visibility. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:175-226`)

This is closer to one request/page use than to an iOS tab+site session. Once capture ends, a repeated Camera+Microphone query prompts again. Every provisional navigation, including reload, revokes media/geolocation runtime state, clears pending queries, and resets the state map; tests cover inactive, active, and paused capture on reload. (`macOS/UnitTests/Permissions/PermissionModelTests.swift:636-708`; `macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:115-125,519-520`)

Same-document history updates do not take the provisional-navigation reset path. A full same-host navigation calls `permissions.tabDidStartNavigation()`, while the same-document callback only publishes an update. The tab owns its runtime `PermissionModel`, and tab deinitialization stops all media; the persisted `.ask` visibility marker is separate. (`macOS/DuckDuckGo/Tab/Model/Tab.swift:187-216,336-337,500-511,1492-1496,1518-1524`)

Pop-ups use a separate page-scoped “Only allow pop-ups for this visit” flag whose copy says it lasts until reload and whose state clears on navigation. This is the macOS “until reload” behavior; it is not the Camera/Microphone grant model. (`macOS/DuckDuckGo/Common/Localizables/UserText.swift:1368-1370`; `macOS/DuckDuckGo/Tab/TabExtensions/PopupHandlingTabExtension.swift:60-71,409-418`)

### Android findings

After a successful OS answer, an unchecked “Remember my choice” writes a Room grant keyed by `(domain, tabId, permissionAllowed)` with a timestamp. Lookups use the same exact tuple. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:506-519`; `android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/sitepermissionsallowed/SitePermissionAllowedEntity.kt:22-37`; `android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/sitepermissionsallowed/SitePermissionsAllowedDao.kt:29-45`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:155-203`)

The validity test is `abs(now - allowedAt) / 3_600_000 <= 24`. Because it uses integer hours, the effective ceiling is just under 25 hours; tests accept 12 hours and reject 25 hours. It survives reload, SPA and same-host navigation, and leaving and returning to the same host in the same tab. Because both the permission row and tab ID are persisted, it can also survive a process/app restart when that same tab is restored; this last point is an inference from the two stores. A genuinely new tab has a new UUID and cannot use it. (`android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/sitepermissionsallowed/SitePermissionAllowedEntity.kt:31-37`; `android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/SitePermissionsDatabase.kt:28-38`; `android/browser-api/src/main/java/com/duckduckgo/app/tabs/model/TabEntitiy.kt:31-57`; `android/site-permissions/site-permissions-impl/src/test/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepositoryTest.kt:221-240`; `android/app/src/main/java/com/duckduckgo/app/tabs/model/TabDataRepository.kt:101-166`)

Closing a tab marks the same tab entity deletable, and Undo restores the same tab ID, so an Undo-close can continue using the grant. Final tab purge still does not delete the site-permission row; after purge the grant becomes unusable only because no live tab owns the old ID. TTL expiry makes the orphan invalid but does not delete it; only domain/all permission cleanup does. (`android/app/src/main/java/com/duckduckgo/app/tabs/model/TabDataRepository.kt:374-412`; `android/app/src/main/java/com/duckduckgo/app/tabs/db/TabsDao.kt:88-125`; `android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/sitepermissionsallowed/SitePermissionAllowedEntity.kt:33-37`; `android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/sitepermissionsallowed/SitePermissionsAllowedDao.kt:29-45`)

### Recommendation for iOS

Retain the proposed in-memory per-tab+site grant and reload survival, but explicitly end it when the top-level site changes and when the tab closes. Do not copy Android's persisted 24-hour TTL or Undo-close survival. Add tests for reload, same-document navigation, cross-site away-and-back, process termination, app termination, restored tabs, tab close, and undo-close. macOS contradicts reload survival; Android contradicts the leave-site and tab-close boundaries. The complete precedent therefore **contradicts** the iOS default.

**Verdict:** `contradicts iOS default`

## 3. Combined Camera+Microphone (OQ-2)

### macOS findings

macOS recognizes WebKit's combined capture type as one authorization query containing Camera and Microphone, passes that array to one `PermissionModel` request, then selects the UI-only `.cameraAndMicrophone` variant. (`macOS/DuckDuckGo/Permissions/Model/PermissionType.swift:175-189`; `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift:103-116`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift:28-43`)

The exact English prompt is:

> Allow “&lt;domain&gt;“ to use your camera and microphone once?

`Camera and Microphone` supplies the combined label and is lowercased into `Allow “%@“ to use your %@ once?`. The dialog has two horizontally arranged buttons, in order: `Deny`, `Allow`. There is no persistent-choice control in this standard dialog. (`macOS/DuckDuckGo/Common/Localizables/UserText.swift:1321-1323,1345-1348,1377-1381`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift:250-256,600-633`)

### Android findings

If both Camera and Microphone still require user handling, Android selects one combined DuckDuckGo dialog. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:111-124`)

Its exact English content is:

- Title: `"<site>" wants to access the camera and microphone`
- Body: `You can manage the microphone and camera access permissions you’ve granted to individual sites in Settings.`
- Controls: `Allow`, `Deny`, and the checkbox `Remember my choice`

(`android/site-permissions/site-permissions-impl/src/main/res/values/strings-site-permissions.xml:30,39,42,46-47`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:216-249`)

Android requests the missing runtime permissions together and denies the combined WebView request if any returned result is false. If one site permission was already automatically accepted, it prompts only for the remaining type and combines the automatic and user-handled results. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:409-439,488-499`)

### Recommendation for iOS

Use one combined iOS dialog and treat site and OS results atomically. The two shipped implementations confirm the current iOS default; only the three-option copy and partial-denial recovery remain to design.

**Verdict:** `confirms iOS default`

## 4. Recovery from OS/app-level denial (OQ-5, OQ-13, FR-5)

### macOS findings

For permission types that use macOS's explicit system gate, a stored site allow is still checked against the current OS state. If the OS is denied, restricted, or disabled, macOS declines the request and publishes `permissionBlockedBySystem` so the view layer can show remediation. The generic two-step gate currently applies to Geolocation and Notifications, not Camera or Microphone. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:391-435,441-479`; `macOS/DuckDuckGo/Permissions/Model/PermissionType.swift:146-153`)

For a fresh Geolocation or Notification request, the authorization view completes the system step before enabling the site's final Deny/Allow step. Those ordinary site buttons submit no “remember” value, so the resulting site record is `.ask`, not persistent Allow/Deny. This system-first ordering differs from iOS's proposed site-choice-first flow. (`macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift:403-493`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationViewController.swift:147-161`; `macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:204-213`)

Camera/Microphone use a separate compatibility hook that intercepts `AVCaptureDevice.authorizationStatus`, because WebKit otherwise skips its permission delegate after an OS denial. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:355-389`)

macOS keeps an existing site allow intact while declining the blocked request. The dedicated information view opens the appropriate System Settings pane and fires a pixel; the separate authorization view rechecks OS state when the app becomes active. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:448-469`; `macOS/UnitTests/Permissions/PermissionModelTests.swift:1233-1264`; `macOS/DuckDuckGo/Permissions/View/SystemDisabledPermissionInfoView.swift:82-93,107-145`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift:344-400`)

### Android findings

The current general site-permission flow does **not** commit the site allow when the user taps Allow. It first requests any missing Android runtime permission. Only `systemPermissionGranted()` writes `ALLOW_ALWAYS` or an Allow Once row and then grants the WebView request. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:409-520`)

A retryable runtime denial shows a long snackbar with `Allow DuckDuckGo to ask for <type> access` and an `Allow` action. The action re-requests the OS permission; timeout denies the outstanding WebView request. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:533-596`; `android/site-permissions/site-permissions-impl/src/main/res/values/strings-site-permissions.xml:35,48-51`)

The retry path also drops an initially checked “Remember my choice”: the denial handler calls the snackbar without the original persistence argument, whose default is false. If the retry later succeeds, it becomes a session-only grant. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:533-540,545-568`)

Only a snackbar timeout resolves the outstanding WebView request with a deny. A swipe, action, or other non-timeout dismissal does not resolve it at dismissal time. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:573-595`)

When no requested resource was autoaccepted, a permanent denial first denies the WebView request, then shows:

- Title: `Allow DuckDuckGo to ask for <type> access on this device`
- Body: `Sites can only use your <type> if you allow DuckDuckGo to ask for access.`
- Buttons: `Open Settings`, `Cancel`

The positive action opens the app-detail settings page. Crucially, if “Remember my choice” was checked, `denyPermissions(true)` stores per-site `DENY_ALWAYS`, replacing the attempted allow. With the checkbox clear, it writes no persistent site decision. If another resource in a combined request was already autoaccepted, Android instead grants that subset and stores no deny. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:598-653`; `android/site-permissions/site-permissions-impl/src/main/res/values/strings-site-permissions.xml:52-59`)

The shipped Voice Search sibling uses live OS state rather than a sticky “denied forever” flag: after its rationale has been accepted it always requests the runtime permission, and only a denied callback with no further Android rationale shows its Settings dialog. Current copy is `Microphone Access Required`, `To use Voice Search in DuckDuckGo you need to enable Microphone access in the system settings.`, with `Settings` and `Cancel`. (`android/voice-search/voice-search-impl/src/main/java/com/duckduckgo/voice/impl/PermissionRequest.kt:53-96`; `android/voice-search/voice-search-impl/src/main/java/com/duckduckgo/voice/impl/PermissionRationale.kt:26-33`; `android/voice-search/voice-search-impl/src/main/res/values/strings-voice-search.xml:24-30`) The live-state fix is commit `9c12c06f3f`, which is contained in public tag `5.289.0` and this checkout's `HEAD`.

Cancel from that no-microphone dialog chains to `Remove Private Voice Search option from the address bar?`; `Remove` disables the feature and `Cancel` leaves it enabled. (`android/voice-search/voice-search-impl/src/main/java/com/duckduckgo/voice/impl/PermissionRequest.kt:84-110`; `android/voice-search/voice-search-impl/src/main/java/com/duckduckgo/voice/impl/VoiceSearchPermissionDialogsLauncher.kt:50-71,98-124`; `android/voice-search/voice-search-impl/src/main/res/values/strings-voice-search.xml:28-33`)

A more extensive `voice-search-default-on` redesign exists in the available local remote refs, but its commits `706411feb7` and patch-equivalent `3bf9611496` are not ancestors of this `develop` HEAD. This checkout therefore verifies the rationale-first shipped flow above, not the newer branch UX.

The transferable precedents are live OS-state re-evaluation, an explanatory dialog, and a Settings deep link. Android's retry snackbar does not transfer because iOS cannot re-trigger a denied system prompt.

### Recommendation for iOS

Commit `Allow While Using Site` at the site-choice step, preserve it if the iOS system prompt is denied, decline the triggering request, and expose the menu/reminder recovery state. Never rewrite the user's site Allow as Never Allow. Recheck OS state on app activation. This intentionally **contradicts** Android's site-permission commit ordering while retaining its useful explanatory-dialog pattern.

**Verdict:** `contradicts iOS default`

## 5. List membership and explicit-Ask rows (OQ-17)

### macOS findings

For Camera, Microphone, and Location, macOS stores `.ask` explicitly after a one-time Allow or Deny to keep the permission visible in Permission Center. Notification has separate persistence rules. The storage encoding uses `isRemoved = true` for `.ask`, but the Core Data row remains until Remove or Fire clears it. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:165-213`; `macOS/DuckDuckGo/Permissions/Model/PermissionManager.swift:117-160,181-194`; `macOS/DuckDuckGo/Permissions/Model/StoredPermission.swift:23-47,81-95`)

Any runtime permission or persisted record, including `.ask`, makes the address-bar Permission Center button eligible. Actual visibility is additionally gated by address-bar focus/input, error-page state, and special-site handling. Selecting `Always ask` in Permission Center updates and retains the stored row rather than deleting it. (`macOS/DuckDuckGo/NavigationBar/View/AddressBarButtonsViewController.swift:859-907,3012-3040`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:289-303`; `macOS/DuckDuckGo/Permissions/View/PermissionCenterView.swift:337-363`)

### Android findings

Android Manage Sites renders every `SitePermissionsEntity`. An initial Camera/Microphone/Location Allow Once creates both the ephemeral allowed row and an all-Ask `SitePermissionsEntity`; that site therefore remains listed even after the temporary grant expires. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/SitePermissionsViewModel.kt:75-83`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:189-203`; `android/site-permissions/site-permissions-impl/src/test/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepositoryTest.kt:254-277`)

Resetting an individual permission to Ask saves the full entity rather than deleting it. The domain disappears only after an explicit per-site delete, Remove All, or a non-fireproof Fire clear. Merely showing a prompt or choosing Deny Once creates no row. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteViewModel.kt:139-201`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:249-267`)

### Recommendation for iOS

Keep explicit user-reset Ask rows listed and keep the menu entry visible for any stored record or active grant. Do **not** copy either platform's temporary-choice marker: iOS's no-passive-record rule is the safer browsing-history boundary. The explicit-Ask portion confirms the default, but both platforms' ephemeral list membership **contradicts** it overall.

**Verdict:** `contradicts iOS default`

## 6. Manager row rules (OQ-18)

### macOS findings

The macOS Permission Center constructs rows from the union of permission types in the current tab's runtime `usedPermissions` map and the domain's persisted permission types. Requested queries are inserted into `usedPermissions` before presentation, so requested-this-visit is naturally part of that union. Popup and autoplay rows have additional feature-specific rules. (`macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:498-558`; `macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:223-226`)

An absent runtime value for a persisted row defaults to `.inactive`; the row still carries its stored decision. (`macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:572-596`)

### Android findings

There is no browser-menu, current-site manager in this Android checkout. The manifest exposes the global Settings activity and its per-site child, and the browser's location affordance opens global Site Permissions. (`android/site-permissions/site-permissions-impl/src/main/AndroidManifest.xml:21-30`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/SitePermissionsScreens.kt:19-24`; `android/app/src/main/java/com/duckduckgo/app/browser/BrowserActivity.kt:1067-1073`)

The existing per-site Settings screen always emits four rows—Location, Camera, Microphone, and DRM—regardless of what is persisted, active, or requested this visit. It reads the stored entity and global controls, not WebView runtime state. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteViewModel.kt:59-123`)

### Recommendation for iOS

Use `stored ∪ active ∪ requested-this-visit`; do not add rows solely because a global type is Never Allow. macOS directly confirms this default for its current-site manager. Android provides no on-site-manager precedent.

**Verdict:** `confirms iOS default`

## 7. In-use and muted indication (OQ-14, OQ-19)

### macOS findings

macOS models `.active`, `.paused`, and `.inactive` separately. WebKit `.muted` maps to `.paused`; a transition back to `.active` restores `.active`, and `.none` becomes `.inactive`. (`macOS/DuckDuckGo/Permissions/Model/PermissionState.swift:22-30,154-191`)

The Permission Center treats only `.active` as “in use.” It renders an active permission as a solid red icon; an Always Allow row is solid but not red, while a paused one-time grant is allowed but not visually “in use.” The image itself has no dedicated status text or accessibility label in this view. (`macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:81-98`; `macOS/DuckDuckGo/Permissions/View/PermissionCenterView.swift:315-335`)

The tab bar likewise includes only active Camera, Microphone, and Geolocation, replaces the favicon with a solid red icon, and rotates every four seconds when multiple permissions are active. Paused/muted capture is omitted. (`macOS/DuckDuckGo/TabBar/View/TabBarViewItem.swift:982-1042`)

The tab's accessibility title remains the page title. The image-only address-bar shield receives an accessibility identifier but no active/paused permission-state title or value in the inspected setup. (`macOS/DuckDuckGo/TabBar/View/TabBarViewItem.swift:490-503`; `macOS/DuckDuckGo/NavigationBar/View/AddressBarButtonsViewController.swift:396-420`; `macOS/DuckDuckGo/NavigationBar/View/NavigationBar.storyboard:999-1021`)

### Android findings

Android's site-permission UI model contains only Ask, globally-disabled Ask, Deny, and Allow. Its per-site adapter exposes those stored/default choices, not a capture state; there is no custom active, muted, or accessible in-use indicator in this feature. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/WebsitePermissionSettingOption.kt:30-45`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionSettingAdapter.kt:52-63`)

### Recommendation for iOS

Do not treat either platform as sufficient precedent. Keep the requirement for a non-color visual and VoiceOver label, and design `.muted` as a distinct paused state rather than silently dropping the indication. Exact copy remains an OQ-14/OQ-19 design decision.

**Verdict:** `no precedent`

## 8. Restricted and system-disabled states (OQ-15)

### macOS findings

The macOS system model distinguishes `denied`, `restricted` (parental controls/MDM), and `systemDisabled` (for example Location Services off). Geolocation maps disabled services and restricted authorization to different model values. (`macOS/DuckDuckGo/Permissions/Model/SystemPermissionManager.swift:29-41,148-164`)

The reusable authorization view collapses all three to `.alreadyDenied` and supplies the same System Settings remediation. This does not mean every state reaches that view in production: Geolocation routes `.systemDisabled` into the two-step view, while an already-denied/restricted authorization can return without that route. (`macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift:327-340,357-379`; `macOS/DuckDuckGo/Permissions/Model/SystemPermissionManager.swift:184-190`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationViewController.swift:99-114`)

The reusable dedicated macOS information view defines this exact generic copy:

- Location prompt: `“<domain>“ website would like to use your current location.`
- Location warning/link: `System location disabled. Turn it on in System Settings → Privacy`
- Microphone prompt: `“<domain>“ website would like to use your microphone.`
- Microphone warning/link: `System microphone access disabled. Turn it on in System Settings → Privacy`

The warning/link area is clickable, opens the corresponding Settings pane, and fires the system-preferences pixel. Camera has no variant in this view, and the routed Microphone remediation is currently Duck.ai-specific, where it substitutes Voice Chat/Dictation copy; treat the generic Microphone text as reusable code, not proof of a general shipped route. (`macOS/DuckDuckGo/Common/Localizables/UserText.swift:1309-1314,1392-1395`; `macOS/DuckDuckGo/Permissions/View/SystemDisabledPermissionInfoView.swift:33-93,107-145`; `macOS/DuckDuckGo/NavigationBar/View/AddressBarButtonsViewController.swift:640-680`)

### Android findings

Android has no equivalent restricted/unavailable presentation in site permissions. Missing camera hardware and disabled Location Services make the resource unsupported; unsupported resources are filtered and a request with nothing left is denied without a dedicated message. Runtime state is otherwise granted/not granted plus the rationale-based “rejected forever” inference that leads to the generic Open Settings dialog. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:92-96,130-135,204-217`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SystemPermissionsHelper.kt:56-64,90-100`)

### Recommendation for iOS

Keep `restricted` and `unavailable` distinct from user-denied and show plain explanatory copy without a Settings button. macOS proves the state distinction is useful but its shared Settings remediation would dead-end in restricted cases; Android offers no usable UI precedent.

**Verdict:** `no precedent`

## 9. Mid-session changes and reload (OQ-11, OQ-20)

### macOS findings

Standard Permission Center decision changes and removals mark reload needed; special popup actions apply immediately through their own path. The banner copy is `Reload for changes to take effect` with a `Reload` button. (`macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:289-321,364-428,469-483`; `macOS/DuckDuckGo/Common/Localizables/UserText.swift:1418-1419`; `macOS/DuckDuckGo/Permissions/View/PermissionCenterView.swift:176-210`)

The implementation is more immediate than the banner suggests. A current-domain change to Deny calls `revoke`, and Remove revokes Camera/Microphone/Geolocation and deletes the stored row immediately. A current pending request can also be resolved immediately by a newly stored decision. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:229-305`)

### Android findings

Global changes write SharedPreferences, and per-site Save writes a Room entity. Neither Settings ViewModel holds a WebView or invokes a capture-stop/reload API. New permission requests reread the repository, so a change applies on the next request; reload matters only if it causes one. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/SitePermissionsViewModel.kt:87-111`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteViewModel.kt:139-201`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:73-146`)

Those edits do not delete existing Allow Once rows. Deny/global-off blocks the next real request, but changing back to Ask before the old TTL expires can make that stale row auto-grant again. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteViewModel.kt:185-201`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:155-184,270-273`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:92-110`)

### Recommendation for iOS

Keep the v1 reload/next-request rule and test that active capture is not stopped by manager/global changes. Android confirms that behavior, while macOS deny/remove contradicts it through immediate revocation. Document the macOS behavior as a deliberate non-goal for v1 rather than assuming the shared reload caption implies identical semantics.

**Verdict:** `contradicts iOS default`

## 10. Privacy defaults: Fire, clearing scope, and storage key

### macOS findings

`PermissionManager.burnPermissions(except:)` retains only records whose domain is fireproof, then clears every other stored record. Its scoped counterpart converts each stored host to eTLD+1 and removes records whose base domain is in the burn set. (`macOS/DuckDuckGo/Permissions/Model/PermissionManager.swift:146-179`)

The FireproofDomains store itself migrates and compares at eTLD+1, so a stored permission on a subdomain survives when its base domain is fireproofed. (`macOS/DuckDuckGo/Fireproofing/Model/FireproofDomains.swift:91-102,115-125,199-202`)

The selected-domain burn calls the scoped permission clear only when Cookies and Site Data is included. The full all-windows burn calls `burnPermissions(except:)` regardless of that cache flag. Permission Center Remove directly deletes one selected permission row with no fireproof exception; macOS has no site-wide manual-delete precedent in this UI. (`macOS/DuckDuckGo/Fire/Model/Fire.swift:478-487,598-630,1001-1009`; `macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:283-304`; `macOS/DuckDuckGo/Permissions/Model/PermissionManager.swift:181-194`)

macOS storage is a Core Data row containing encrypted domain, permission-type raw value, and decision. Reads and writes remove only the exact lowercase prefix `www.` and otherwise use the host string; scheme and port never enter this key, and non-`www` subdomains remain distinct. Permission matching is not eTLD+1—eTLD+1 is used by scoped Fire only. The delegate supplies the requesting `WKSecurityOrigin.host` for media and the requesting frame's host for Geolocation, rather than a guaranteed top-level committed host; file requests share the synthetic `localhost` key. (`macOS/DuckDuckGo/Permissions/Model/PermissionStore.swift:154-180`; `macOS/DuckDuckGo/Permissions/Model/PermissionManager.swift:73-77,91-120,163-169`; `SharedPackages/Infrastructure/SystemFrameworksExtensions/Sources/FoundationExtensions/StringExtension.swift:53-63`; `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift:105-160`)

macOS has no matching global Camera/Microphone/Location defaults to test for preservation. The closest global permission preference, Autoplay, is stored separately in UserDefaults and is not touched by per-site `PermissionManager` clearing. Burner tabs replace the favicon cache but receive the same application-level `PermissionManager` used by regular tabs, so macOS has no separate fire-mode permission read/write exclusion. (`macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift:43-64`; `macOS/DuckDuckGo/Permissions/Model/PermissionManager.swift:146-179`; `macOS/DuckDuckGo/Tab/Model/Tab.swift:175-216,336-337`)

### Android findings

The default regular Fire configuration includes Tabs and Data, so it clears site permissions. When `DATA` is included, the browser-data path passes raw fireproof hosts to `SitePermissionsManager`; a configured tabs-only clear does not. A Fire-button clear while already browsing in `BrowserMode.FIRE` runs its mode-only clear and likewise does not call the shared browser-data path. (`android/app/src/main/java/com/duckduckgo/app/fire/store/FireDataStore.kt:139-185`; `android/app/src/main/java/com/duckduckgo/app/fire/DataClearing.kt:162-202,291-304`; `android/app/src/main/java/com/duckduckgo/app/global/view/ClearPersonalDataAction.kt:145-160,219-228`)

The manager clears the central `DrmSessionStore` and deletes each non-fireproof site's permanent entity and temporary rows. For an exact fireproof-domain match it skips that domain delete, so both the persistent entity and an Allow Once row survive. The legacy flag-off DRM session map is separate and has no explicit clear in this path. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:149-156`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:106-120,189-203,218-231,261-267`; `android/site-permissions/site-permissions-impl/src/test/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerTest.kt:348-378`)

The narrower regular-mode `clearDataForSpecificDomains()` path does not call `SitePermissionsManager`, so that single-tab/domain clearing operation can leave site-permission rows behind. (`android/app/src/main/java/com/duckduckgo/app/fire/DataClearing.kt:83-110`; `android/app/src/main/java/com/duckduckgo/app/global/view/ClearPersonalDataAction.kt:180-210`)

Manual per-site deletion and Remove All bypass fireproofing. A per-domain delete removes both the permanent entity and temporary allowed rows. Global ask controls live in separate SharedPreferences and are untouched by Fire, per-site deletion, or Remove All. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteViewModel.kt:132-136`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/SitePermissionsViewModel.kt:120-135`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:249-267`; `android/site-permissions/site-permissions-store/src/main/java/com/duckduckgo/site/permissions/store/SitePermissionsPreferences.kt:32-57`)

Fire-mode browsing itself does not persist grants, denies, DRM choices, or permission favicons. It still calls the same `getSitePermissions()` path and reads shared stored decisions, however, because BrowserMode is applied only in the launcher's write guards. Android therefore confirms “never write” but contradicts iOS's “never read.” (`android/app/src/main/java/com/duckduckgo/app/browser/BrowserChromeClient.kt:148-157`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:64-146`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:318-337,349-364,506-520,598-615,656-664`)

Android begins the decision path with `request.origin`, then keys lookups and writes with `url.extractDomain() ?: url`; `extractDomain()` uses `Uri.host` for HTTP(S). Scheme, port, and path collapse, exact subdomains remain, and `www.` remains. Tests explicitly expect `www.foo.com`. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:73-80`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:123-125,155-158,189-202,261-280`; `android/common/common-utils/src/main/java/com/duckduckgo/common/utils/UriExtension.kt:156,247-255`; `android/app/src/test/java/com/duckduckgo/app/global/UriExtensionTest.kt:275-280`)

### Recommendation for iOS

Ratify Fire's fireproof exemption, manual removal of all rows, per-site-only clearing, and preserved globals. Keep fire-mode no-read/no-write as a deliberate iOS privacy choice: Android confirms only no-write, and macOS confirms neither half. Keep host-only scheme/port collapse, but ask privacy to explicitly choose top-level committed host + leading-`www.` removal because Android preserves `www.` and both precedents can key from the requester. Add exact-host/fireproof normalization tests.

The fireproof exemption and per-site-only/global-preserved clearing are confirmed. Fire-mode no-read and parts of the storage-key default are contradicted, so the section's overall tag is a contradiction.

**Verdict:** `contradicts iOS default`

## 11. Android tiered three-option prompt status

### macOS findings

The shipped macOS one-time authorization prompt has only `Deny` and `Allow`; persistent choices live in Permission Center as `Always ask`, `Always allow`, and `Never allow`. It is not a tiered three-option prompt precedent. (`macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift:600-633`; `macOS/DuckDuckGo/Permissions/View/PermissionCenterView.swift:337-363`)

### Android findings

The tiered three-option site prompt is **not present or flag-gated in the inspected `develop` checkout**. The reachable prompt is `Allow` and `Deny` plus `Remember my choice`; telemetry maps the combination to `allow_once`, `allow_always`, `deny_once`, or `deny_always`. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:216-249,373-406`; `android/site-permissions/site-permissions-impl/src/main/res/values/strings-site-permissions.xml:30,46-47`)

The relevant shipped feature definitions cover Microphone-domain recovery and DRM policy, not a tiered prompt or on-site manager. An exhaustive search of the checkout and available local history found no tiered-prompt flag or the iOS three-label copy. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/feature/MicrophoneSitePermissionsDomainRecoveryFeature.kt:23-29`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/feature/DrmPolicyFeature.kt:25-39`)

The Settings picker—not the prompt—uses `Ask every time`, `Deny`, and `Allow`. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteActivity.kt:141-170`; `android/site-permissions/site-permissions-impl/src/main/res/values/strings-site-permissions.xml:70-74`)

Dormant four-button resources read `Always`, `Only for This Session`, `Deny for This Session`, and `Deny Always`; lint marks them unused, and the live dialog does not inflate that layout. No current reachable prompt copy says `Allow Once`, `Allow While Using Site`, or `Never Allow`. (`android/app/src/main/res/layout/content_site_location_permission_dialog.xml:54-76`; `android/app/src/main/res/values/strings.xml:515-521`; `android/app/lint-baseline.xml:10951-10993`)

The Android on-site-manager sibling is likewise absent from this checkout; only the Settings activities described in section 6 are present. With no fetch allowed, this establishes “absent from this checkout and available local refs,” not “no external branch exists.”

### Recommendation for iOS

Do not wait for, or copy, an Android tiered implementation that this checkout cannot verify. Continue with the iOS labels `Allow Once`, `Allow While Using Site`, and `Never Allow`, subject to design/copy approval and combined-request copy.

**Verdict:** `no precedent`

## 12. Pixels

### macOS findings

macOS defines these wire-name families:

- `m_mac_permission_authorization_<type>_<allow|deny>`
- `m_mac_permission_center_changed_<type>_to_<ask|allow|deny>` with parameter `from`
- `m_mac_permission_center_reset_<type>`
- `m_mac_permission_system_preferences_<type>`

Authorization supports Camera, Microphone, Geolocation, Popups, Notification, and External Scheme. Permission Center change/reset additionally supports Autoplay Policy; System Preferences is limited to Camera, Microphone, Geolocation, and Notification. Registered standard parameters are `appVersion`, `pixelSource`, and `channel`; change also carries `from`. A combined Camera+Microphone decision fires one authorization event per type. (`macOS/DuckDuckGo/Statistics/PermissionPixel.swift:24-97,117-137`; `macOS/PixelDefinitions/pixels/definitions/permission_pixels.json5:1-72`; `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationViewController.swift:169-174`)

The implementation measures a committed Permission Center change and reset, but not generic manager open, attempted-but-not-completed change, or manager abandonment. Its permission-specific dimensions are type/decision and `from`; registered standard context is app version, pixel source, and channel. No domain is present. (`macOS/DuckDuckGo/Statistics/PermissionPixel.swift:35-65,85-97`; `macOS/PixelDefinitions/pixels/definitions/permission_pixels.json5:1-72`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:289-303,469-479`)

A separate one-time Autoplay discoverability promo measures `shown`, `engaged`, `autoDismissed`, and `settingsLinkClicked`; `engaged` fires when the pointer reaches the auto-opened Permission Center. This is promo-only engagement, not a generic manager-open or abandoned-edit event. (`macOS/DuckDuckGo/Statistics/AutoplayPromoPixel.swift:21-50`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:278-287`; `macOS/DuckDuckGo/Permissions/Promo/AutoplayDiscoverabilityPromoDelegate.swift:86-104`)

### Android findings

Current site-permission pixels are:

- `m_site_permissions_dialog_impresssion`—the spelling with three `s` characters is the current wire name; parameter `type`
- `m_site_permissions_dialog_click`; parameters `type`, `selection`
- `m_site_permissions_auto_granted`; `type=drm`, `reason=allow_list|protections_off`, registered `appVersion`, and `form_factor` suffix
- `ms_site_permissions_pressed`; Settings → Permissions entry, no explicit custom parameter

(`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsPixelName.kt:21-44`; `android/PixelDefinitions/pixels/definitions/site_permissions.json5:1-23`; `android/app/src/main/java/com/duckduckgo/app/pixels/AppPixelName.kt:199`; `android/app/src/main/java/com/duckduckgo/app/permissions/PermissionsViewModel.kt:96-99`)

Prompt types are `location`, `camera`, `microphone`, `camera_and_microphone`, and `drm`; selections are `allow_always`, `allow_once`, `deny_always`, and `deny_once`. The click does not encode the Android runtime-permission outcome: when Camera/Microphone/Location OS access is missing it can fire immediately after launching that request, while already-authorized and DRM paths can complete before it fires. Treat `allow_*` as site-dialog selection, not guaranteed end-to-end success. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:111-204,223-241,280-338,391-406,409-478,506-520`)

The auto-grant event covers central-policy DRM grants only, when the DRM policy/central-policy flags enable that path, and is deduplicated once per tab/domain; remembered user grants are not reported through it. The flags default off for release builds and are always enabled internally. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/feature/DrmPolicyFeature.kt:25-39`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:80-90,182-201`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/drm/DrmSessionStore.kt:35-46`)

Beyond the Settings entry click, Android has no confirmed-screen impression, site-row-open, state-change, remove, undo, or abandonment event. Its row dialog has Save/Cancel and Save writes immediately; there is no screen-level dirty draft. Remove All is immediate with Snackbar Undo restoring the saved permanent and temporary rows, also without permission pixels. No current site-permission pixel map includes a domain, and prompt ATB is explicitly stripped. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/SitePermissionsViewModel.kt:38-42,120-135`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/SitePermissionsActivity.kt:112-122`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsRepository.kt:238-252`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteActivity.kt:141-170`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteViewModel.kt:39-42,139-201`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:366-406`; `android/app/src/main/java/com/duckduckgo/app/global/api/PixelParamRemovalInterceptor.kt:104-105`)

### Recommendation for iOS

Mirror macOS terminology for authorization/change/reset and align cross-platform analysis on normalized `type` and decision/selection. Add explicit manager open, attempted change, committed change, removal, undo, reminder, and abandonment semantics for OQ-16. Never attach a domain. Record site-choice intent separately from OS-success outcome, and do not copy Android's misspelled event name into new iOS definitions.

Neither platform supplies the required abandoned-change measurement.

**Verdict:** `no precedent`

## 13. Additional edge cases the iOS documents should cover

### macOS findings

- macOS permission types extend beyond the iOS v1 scope to Popups, Notifications, External Schemes, and Autoplay Policy. External schemes are grouped into one Permission Center row, while autoplay has its own always-present/discovery rules. Keep these explicitly out of iOS v1. (`macOS/DuckDuckGo/Permissions/Model/PermissionType.swift:25-73`; `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift:517-558`)
- Legacy macOS capture mapping explicitly ignores display capture. Keep screen/display capture named as out of scope rather than letting it fall through implicitly. (`macOS/DuckDuckGo/Permissions/Model/PermissionType.swift:191-205`)
- The macOS key can come from the requesting frame rather than the top-level site, especially for geolocation. This reinforces the need for the iOS top-level/requester split already described in `tech-design.md`. (`macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift:105-116,143-160`)
- File-origin media/geolocation requests share the synthetic `localhost` key. Define internal/file-page behavior explicitly on iOS. (`macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift:120-160`)
- A one-time macOS Deny suppresses repeated requests for the current page, while a one-time Allow can be queried again after capture ends. Navigation clears both runtime outcomes. iOS should specify repeated-request behavior for both choices, not only the Allow Once expiry. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:391-410,519-520`; `macOS/UnitTests/Permissions/PermissionModelTests.swift:670-708,710-730`)
- macOS deliberately keeps Geolocation `.active` after the provider stops reporting current activity so the manager remains discoverable. Do not infer live sensor use from “used/granted” state without a separate signal. (`macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:139-157`; `macOS/UnitTests/Permissions/PermissionModelTests.swift:131-137`)
- macOS combined stored-state rules are deny-wins, both-Allow grants, and partial Allow+Ask prompts. Navigation also resolves pending permission queries as denied. Add both matrices to iOS coordinator tests. (`macOS/UnitTests/Permissions/PermissionModelTests.swift:280-319,739-795`)

### Android findings

- DRM/protected media is a first-class fourth site permission with global and per-site Settings rows. It should remain explicitly out of iOS v1. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:80-90,204-206`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/ui/permissionsperwebsite/PermissionsPerWebsiteViewModel.kt:96-123`)
- Android denies Geolocation unless the requester and top-level page share eTLD+1; Camera/Microphone do not use that extra app-level guard. iOS iframe attribution and Permissions Policy tests should cover same-origin, same-site, and cross-site requesters. (`android/app/src/main/java/com/duckduckgo/app/browser/BrowserTabViewModel.kt:2706-2733`)
- Android's Permissions API bridge maps only Camera and Microphone; other types, including Geolocation, return denied through that bridge. This is a concrete compatibility gap the iOS PR 5/6 transition table must avoid. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:158-172,220-225`)
- Android's Permissions API query checks an existing grant before allowed-to-ask, while a real request applies allowed-to-ask first. A live temporary row can therefore report Granted after a new global/per-site denial even though the next actual request is denied. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:92-110,158-169`)
- Android classifies a combined runtime denial using only the first permission supplied to its rationale check. The Camera+Microphone request puts Microphone first, so a permanent Camera-only denial can be misclassified. Do not copy this shortcut into the iOS partial-state matrix. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SystemPermissionsHelper.kt:90-100`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:430-437,488-493`)
- The fragment-scoped Android dialog launcher stores one mutable outstanding request and has no FIFO. If a dialog command reaches an inactive tab, the fragment returns without resolving it. The iOS coordinator's FIFO and navigation-generation cancellation tests are justified. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:76-109`; `android/app/src/main/java/com/duckduckgo/app/browser/BrowserTabFragment.kt:6680-6693`)
- Duck.ai Microphone bypasses the general site rationale and forces a nonpermanent choice, but regular mode still writes the normal temporary Room grant after OS success. Preserve the explicit iOS Duck.ai exception and test its exact persistence policy. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:126-139,442-445,506-519`; `android/site-permissions/site-permissions-impl/src/test/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncherTest.kt:219-244`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:100-108,228`)
- Android Fire-mode permission decisions are nonpersistent, but Fire tabs still consume shared stored decisions. This supports making iOS's stronger no-read/no-write invariant explicit as a deliberate divergence. (`android/app/src/main/java/com/duckduckgo/app/browser/BrowserChromeClient.kt:148-157`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsManagerImpl.kt:64-146`; `android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:318-337,506-520,598-615`)
- DRM `Learn More` dismisses the dialog, denies the pending request, and only then opens its external URL. Whereby has a site-specific post-grant reload that appends `?skipMediaPermissionPrompt`. Include external-navigation and site-workaround interactions in regression tests. (`android/site-permissions/site-permissions-impl/src/main/java/com/duckduckgo/site/permissions/impl/SitePermissionsDialogActivityLauncher.kt:290-299,524-529`; `android/app/src/main/java/com/duckduckgo/app/browser/BrowserTabFragment.kt:6726-6729`)

### Recommendation for iOS

Add explicit tests or out-of-scope statements for iframe attribution, repeated Deny, concurrent requests/tab changes, protected media, Duck.ai, Permissions API Geolocation, and fire-mode persistence. These are additions rather than confirmations of a single existing default.

**Verdict:** `no precedent`

## Summary: kick-off and open-question mapping

| Finding | Main platform signal | Kick-off discussion item | Requirements question | Verdict |
|---|---|---:|---|---|
| Global precedence | Android site Allow overrides global off | 1 | OQ-8 | `contradicts iOS default` |
| Allow Once lifetime | macOS resets on reload; Android persists tab+host for ~24h | 3 | OQ-9 | `contradicts iOS default` |
| Combined Camera+Microphone | Both platforms use one combined site dialog | 2 | OQ-2 | `confirms iOS default` |
| OS-denial recovery/commit order | Android commits only after OS success and can store Deny | 4, 12 | OQ-1, OQ-5, OQ-13 | `contradicts iOS default` |
| Explicit Ask/list privacy | Explicit Ask remains, but temporary allows also leave rows | 13 | OQ-17 | `contradicts iOS default` |
| On-site row membership | macOS uses persisted ∪ runtime/requested | 14 | OQ-18 | `confirms iOS default` |
| In-use/muted state | macOS has active/paused state but icon-only active UX | 7 | OQ-14, OQ-19 | `no precedent` |
| Restricted/unavailable | macOS models but conflates remediation; Android has no dedicated UX | 8 | OQ-15 | `no precedent` |
| Mid-session changes | Android applies next request; macOS can revoke immediately | 12 | OQ-11, OQ-20 | `contradicts iOS default` |
| Fire/fireproof/global clearing/key | Clearing mostly aligns; both platforms read stored state in private/Fire tabs, and Android preserves `www.` | 9, 10 | OQ-7, OQ-10, OQ-21 | `contradicts iOS default` |
| Tiered Android prompt | Not present in inspected `develop`; live UI is buttons + checkbox | 2/internal sequencing | FR-1, OQ-2 | `no precedent` |
| Pixels | Type/decision naming exists; abandoned-change measurement does not | 11 | OQ-16 | `no precedent` |
| Additional edge cases | DRM, iframes, concurrency, Duck.ai, Fire mode | 9, 12, 14 | OQ-10, OQ-18, OQ-21 | `no precedent` |

## Privacy-test-pages fixtures

The fixture checkout was inspected at `647ae40` (`2026-07-17T14:11:09-06:00`, `main`, `origin/main`) without fetching.

The required base fixtures already exist:

- `features/geolocation.html` repeatedly calls `navigator.geolocation.getCurrentPosition`, reports coordinates/errors, and exposes background-update behavior. (`fixtures/features/geolocation.html:18-27,49`)
- `features/permissions-api.html` queries Camera, Microphone, Geolocation, Notifications, and Push; it exercises `navigator.permissions.query`, Camera/Microphone `getUserMedia`, Geolocation requests, and `PermissionStatus` change listeners. (`fixtures/features/permissions-api.html:60-81,110-170,235-310,343-397`)
- `features/iframe-permissions.html` exercises first-party, same-origin iframe, and cross-origin iframe requests for Geolocation, Camera, Microphone, and DRM, with explicit `allow` attributes and storage-identity test instructions. (`fixtures/features/iframe-permissions.html:175-181,192-200,236-251,256-308,456-502`)
- `features/iframe-media-prompt.html` and `features/iframe-media-prompt-child.html` provide a cross-origin Camera prompt reproduction using `enumerateDevices()` followed by `getUserMedia({ video: true })`. (`fixtures/features/iframe-media-prompt.html:142-148,198`; `fixtures/features/iframe-media-prompt-child.html:103-151`)
- `features/device-enumeration-chaos/main.js` includes separate Camera, Microphone, and combined `getUserMedia({ video: true, audio: true })` operations, although it is a broad device-enumeration stress page rather than a minimal combined-permission fixture. (`fixtures/features/device-enumeration-chaos/main.js:734-765`)
- The fixture index links the Geolocation, Permissions API, iframe-permissions, iframe-media, and device-enumeration pages. (`fixtures/index.html:34-35,64-66`)

PR 5 should extend rather than recreate these fixtures. Current gaps are a dedicated minimal combined Camera+Microphone page, an Allow Once reload/navigation/tab-close matrix, OS-denied recovery, and a manager-originated mutation while an existing `PermissionStatus` change listener is attached. The current Permissions API page already tests Camera change listeners. (`fixtures/features/permissions-api.html:353-397`)

## Recommended documentation edits (do not apply in this investigation)

### `requirements.md`

1. Under OQ-8, record that Android is intentionally opposite: per-site Always Allow overrides global off. Keep the iOS absolute rule and name it as a ratified privacy/product choice.
2. Replace OQ-9's remaining ambiguity with an explicit lifecycle table covering reload, SPA/same-host navigation, cross-site navigation, redirects, Web Content process death, app termination, restored tabs, and tab close. State that the grant is in-memory and never receives Android's 24-hour persistence.
3. Resolve OQ-13 in favor of committing the site Allow at choice time and add the invariant “an OS denial never converts a site Allow into Never Allow.” Tie this directly to OQ-5 menu/recovery visibility.
4. Strengthen the no-passive-record rule: neither a displayed prompt nor Allow Once/Deny Once creates a Settings row; only persistent choices and an explicit manager reset to Ask do. Note that this deliberately differs from macOS and Android.
5. Make OQ-10's fire-mode no-read/no-write behavior a normative requirement, explicitly state that global Never still applies, and record that this is stronger than Android's no-write-only behavior and macOS Burner behavior.
6. Resolve OQ-15 to separate user-denied from restricted/unavailable and forbid a Settings button when Settings cannot fix the state.

### `tech-design.md`

1. Add precedence tests for global Never + stored Allow; Fire-mode isolation tests proving stored per-site state is neither read nor written; and storage-key tests for top-level versus requesting iframe, scheme, port, leading `www.`, exact subdomains, and fireproof matching.
2. Define Allow Once as coordinator-owned in-memory state and list every invalidation event; add cleanup tests proving no persistent marker or restored-tab grant.
3. Specify the recovery transaction order: persist the site decision, request/check the OS permission, decline the current WebKit request on OS denial, retain the site decision, refresh OS state on activation, and expose recovery.
4. State that v1 manager/global changes do not stop active capture, even though macOS does; add reload/next-request tests.
5. Add a precise active/paused presentation contract with visible text and VoiceOver output before implementing OQ-14/OQ-19.
6. Reuse the existing privacy-test-pages fixtures in PR 5 and add only the missing combined/lifecycle/recovery cases listed above.

### `kickoff.md`

1. Put the material contradictions from the headline table at the start of items 1, 3, 4, 10, 12, and 13 so ratification is explicit rather than implied.
2. Update the Android sibling status: the inspected shipped prompt is Allow/Deny + Remember; the tiered three-option and on-site manager implementations are absent from this `develop` checkout. Distinguish that from the shipped Voice Search live-OS-state recovery flow.
3. For item 11, define separate events for manager open, edit begun, edit committed, dismissal with dirty state, remove/undo, reminder shown, and Settings tap; forbid domains in every payload.
