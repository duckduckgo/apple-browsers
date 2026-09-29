# Prompt: implement the Build 2 design-review fixes (per-site permission manager, iOS)

You are implementing the fixes the designer (Sveta) filed after testing Alpha build 7.237.0 of the iOS per-site permission manager. Asana parent task: https://app.asana.com/1/137249556945/task/1218248622567555 ("Build 2"). You have no Asana or Figma access — everything you need is below and in the docs on branch `bartosz/on-site-permissions` (`docs/on-site-permission-manager/`: requirements.md, tech-design.md, implementation-plan.md — read the plan's working rules §2 first, they all apply: XcodeBuildMCP for builds and selected tests, no manual simulator testing without permission, UI yield rule, never push, clean commits with the Claude co-author trailer, per-phase independent review with Ponytail pass, project log on the docs branch).

**Branch:** create `bartosz/on-site-permissions-7` off `origin/bartosz/on-site-permissions-6` (top of the open stack; PRs 1–3 are merged, 4–6 are open). Land all fixes below as one PR. Write `docs/on-site-permission-manager/pr7-description.md` on the docs branch when done (Asana task for the PR body: the parent task above).

**Verification site:** https://permissions.kunat.dev/ (the page the designer used; it can trigger camera, microphone, location, and combined requests).

## Fixes to implement

### 1. Bug — "Site Permissions" menu item missing after a location-only Allow Once
Repro: on a fresh site, trigger the location dialog, tap Allow Once → the browser menu shows no "Site Permissions" item. Trigger camera and allow → the item appears and lists both.
Root cause (verified): `SitePermissionsManagementSnapshot.showsMenuEntry` (`Management/SitePermissionsManagementSnapshot.swift:65`) is true only for a stored record, an `allowOnce` entry, a `siteAllowedPermissionTypesThisVisit` entry, or an active capture. The geolocation provider's `locationActivityHandler` (`TabViewController+SitePermissions.swift:~795`) flips the location capture to `.inactive` the moment a one-shot `getCurrentPosition` completes; `updateCaptureState` then calls `captureDidEnd` (`SitePermissionsCoordinator.swift:~497–499`), which **removes** the type from both `allowOnce` and `siteAllowedPermissionTypesThisVisit` (`~306–309`). Camera only works because its capture stays active.
Fix: `captureDidEnd` clears capture state only. The page-scoped grant sets (`allowOnce`, `siteAllowedPermissionTypesThisVisit`) clear on navigation/reload per the ratified Allow Once lifetime — never on capture end. Check that Allow Once's "may re-prompt after capture ends" behavior is still driven by `deniedForPage`/capture state, not by dropping the grant. Tests: location Allow Once keeps the menu entry visible for the rest of the page; camera path unchanged; grants still end on reload.

### 2. Dialog icon container: 16pt corners; camera glyph from DesignResourcesKit
`UI/SitePermissionDialogView.swift`: `iconContainerCornerRadius` 12 → **16** (continuous corners). Verified in Figma (dialog component 372:7918): the icon tile is a 48pt square (24pt glyph + 12pt padding) with 16pt corners on the tertiary container fill — the current 48pt tile size and 12pt inner padding already match; only the radius changes. Replace the SF Symbol `video` for camera with `DesignSystemImages.Glyphs.Size24.video` (asset `Video-24`, the designer's `Video-24-1.svg`). Replace SF `microphone`/`mic` with `DesignSystemImages.Glyphs.Size24.microphone` for consistency (same asset family; flag in the PR if you think it should stay SF).

### 3. Copy: an active Allow Once shows "Ask Each Time", not "Allow(ed) This Time"
Design decision (Figma component set 442:113096 has only Ask Each Time / Never / Always, with in-use as a separate axis). In the on-site sheet row and its picker, an active ephemeral grant must read `Ask Each Time` plus the in-use indicator. Remove the `Allow This Time` string and any code path that showed it (requirements FR-4 and the implementation plan were already updated to say this).

### 4. Reload caption only after a change in the sheet
`Management/SitePermissionsSheetView.swift:66–69` shows `Reload the page for changes to take effect.` whenever `state == .permissionsOnly`. Show it only after the user has changed a permission during the current sheet presentation: add a dirty flag to `SitePermissionsSheetViewModel` (set on any committed picker change), render the caption from it, reset when the sheet closes. Identifier `SitePermissions.Sheet.ReloadCaption` stays.

### 5. Manage Sites swipe-to-delete: match Bookmarks
`SettingsSitePermissionsView.swift:254–255` uses `.swipeActions` with a text `Delete` button. Make it icon-only with `DesignSystemImages.Glyphs.Size24.trash` (as `BookmarksViewController.swift:392` does), `role: .destructive`, and an accessibility label. For the rounded action button and rounded row edge, use the inset-grouped list style on the Manage Sites list if it isn't already. Verify against Bookmarks side by side.

### 6. Dialogs dismissible by tapping outside — dismissal = one-time deny (decided)
The 3-option dialog is a full-screen child `UIHostingController` overlay (`TabViewController+SitePermissions.swift:~1052–1074`) with no scrim tap handling. Add a tap on the dimmed background that dismisses the dialog and resolves the request as **cancel = one-time deny**: decline the request, add the type to the page-scoped `deniedForPage` set (no re-prompt on this page load; a reload/navigation lets the site ask again), persist nothing, create no Settings record; `permissions.query` reports `denied` for the rest of the page load, consistent with the request outcome. Pixel: fire `permission_dialog_click_<type>_dismissed` (new `dismissed` selection token — add it to the event enum, the app-side mapping, and `site_permissions.json5`; run `npm run validate-pixel-defs`). Apply the same tap-outside dismissal to the reminder dialog (equivalent to Cancel).

### 7. Reminder ("denied system permissions") dialog: larger top padding
Figma (component 380:46544, Apple-alert based): card padding 14 + text-block inset 8 → **22pt** top and side padding around the title/body; 24pt below the text block plus a 10pt gap before the buttons. Current `UI/PermissionReminderDialogView.swift`: sides are 14+8 = 22 ✓, but the text block has no top inset (14 total). Add an 8pt top padding to the title/body block so top equals the sides. Figma applies the same text-block insets (top 8 / sides 8 / bottom 24) to the 3-option dialog too — check `SitePermissionDialogView` and align it if it differs. Leave card radius/width as they are unless asked.

### 8. Combined camera+mic request when one type's global default is Never Allow — keep as is, document it
Designer's report: with Camera set to "not allowed to ask" globally, a site requesting camera+mic gets no dialog. This is intended and cannot be changed within WebKit: `requestMediaCapturePermissionFor` gives **one** decision for a `.cameraAndMicrophone` request — grant means both devices. Granting "mic only" is impossible, and prompting would let a site bypass the global camera block by bundling. The coordinator already returns `.deny` (`SitePermissionsCoordinator.swift:~286`). Work: add a code comment stating this, and add a unit test pinning it (camera global Never + mic Ask + combined request → deny, no prompt; a mic-only request still prompts). No behavior change.

## Closed by the designer — no action
- Keep the permission entry when the OS prompt was denied (matches desktop).
- No animation on denial (and the grant animation is cut from v1 anyway).

## Done criteria
Build green; `SitePermissions` package tests and touched app suites pass via XcodeBuildMCP; each fix verified against the acceptance notes above; new/changed strings marked for copy review; the independent review loop run; `pr7-description.md` written on the docs branch; project log updated. Never push.
