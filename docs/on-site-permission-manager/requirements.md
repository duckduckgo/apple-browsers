# [iOS] On-site Permission Manager & Updated Permission Dialogues — Requirements Specification

**Status:** Active (taken off hold 2026-08-24, decision by Chris Thelwell)
**DRI:** Bartosz · **Project Advisor:** Brindy · **Design:** Sveta · **Copy:** David A
**Due:** 2026-09-11 · **Estimate:** ~17–18 person-days across a 7-PR stack (tech-design §5)
**Main Asana task:** https://app.asana.com/1/137249556945/project/1215172677539195/task/1213800892997347
**Parent problem:** "Permission Prompt Experience" — https://app.asana.com/1/137249556945/task/1213911423943411

This document gathers every requirement, decision, constraint, and open question from the Asana project (main task, its comment history, linked tasks, privacy triages, design peer review, tech input) and the Figma design file. It is deliberately implementation-independent; the companion [tech-design.md](tech-design.md) covers the how.

> **Delivery plan:** the work breakdown (one Asana subtask per stacked PR, with estimates) is in [tech-design.md](tech-design.md) §5.

---

## 1. Problem & Motivation

- iOS users report being unable to use website functionality (camera/mic/location) — usually because they previously denied a permission and there is **no way to find or change that decision**. Evidence ("iOS: Permission prompt handling", https://app.asana.com/1/137249556945/task/1212343625229910):
  - id.me: 173 breakage reports in 3 months, >60% iOS
  - veriff.me: 16 breakage reports in 3 months, almost all iOS
  - Sniffies: iOS reporting rate double Android's (opposite of the usual trend)
  - Sample reports: "Asked to unblock camera access. Unblocked, but still didn't allow access."
- Today iOS only supports **per-session** site permissions: WebKit shows its own 2-option prompt, and the OS-level system prompt is effectively asked **before** the user has meaningfully engaged. The iOS system prompt is **one-and-done**: a single "Don't Allow" locks the entire app out of that permission for **all** websites, with no way to re-trigger the prompt — the root of the recovery problem.
- Per-site permissions on iOS are an industry gap: Safari hides it, Firefox and Brave don't offer it, Chrome/Edge only surface it via a post-grant banner.
- The per-site permission manager already shipped on Desktop — the model is proven; this is the iOS follow-on.

### Success criteria (from the main task)

1. Per-site permission manager shipped to **100% of iOS users**, per the design spec — covering **camera, microphone, and location**, with Fire Button integration.
2. Directional reduction in the iOS permission issue rate from the **4.0% baseline** — measured via permission-manager engagement (opens, changes) in the 4 weeks post-launch as an interim signal, confirmed via the Quarterly Survey the following quarter.

### Parent-problem KPIs (context)

- Prompt Suppression Rate: >80% of permission needs never reach the user.
- Prompted Experience Success Rate: >90%. Friction signals (need new pixels) include: deny → re-trigger same feature → leave within 30s; breakage report in the same session after a permission interaction; user opens the permission manager, attempts a change, doesn't complete it.

---

## 2. Scope

### In scope

Permission types: **Camera, Microphone, Location (geolocation)** — only these three.

1. **3-option site permission dialogue** replacing WebKit's default prompt, for all three types (plus a special DuckDuckGo-SERP location variant).
2. **Reversed dialogue order**: DDG's site-level dialogue first; the OS system dialogue only after (and only if) the user allows — protecting the one-shot OS prompt.
3. **On-site permission manager**: a "Site Permissions" entry in the browser menu (conditionally shown) opening a per-site bottom sheet where users view/modify/remove the current site's permissions.
4. **Settings > Site Permissions**: global per-type defaults (Ask Each Time / Never Allow), list of sites with stored permissions, per-site editing, remove-one / remove-all.
5. **Recovery from denied system permissions**: reminder dialogue + "Go to System Settings" links (deep link to Settings → Apps → DuckDuckGo).
6. **Visual feedback**: grant animation; status icons (outline / solid / blocked / red-in-use) throughout the manager surfaces.
7. **Fire Button / fireproofing integration** for stored permissions.

### Out of scope (explicitly descoped or deferred)

- **Address-bar permission indicator and post-grant banner/sheet** — part of the project's original scope, replaced by the menu entry point after the Design Peer Review (see §4.1).
- **Per-session live toggles in the on-site sheet** — proposed late, rejected (misleading semantics; mid-session changes likely require a page reload). May be re-evaluated during implementation in a real build.
- Other permission types (notifications, pop-ups, autoplay, device motion). Tech input confirmed pop-ups/device-motion are feasible and autoplay needs extra plumbing — all future candidates, none in scope.
- Android work (sibling projects) and the Android-specific voice-search flow.
- Re-triggering the OS system prompt after denial — **impossible on iOS for every permission type** (hack-phase confirmed).
- Syncing permission state across devices — privacy triage mandates **local device state only**.

---

## 3. Established Technical Facts (from tech input + hack phase — both validated)

Source: "[Tech input] Permissions on iOS" (https://app.asana.com/0/1214732727456025/1214732727456025) and the hack phase completed in July 2026.

1. **Camera/mic:** a delegate hook exists; the current dialog can be replaced with a 3-option flow directly.
2. **Geolocation:** WebKit shows its own location prompt on iOS with **no delegate hook**. The workaround — intercepting `navigator.geolocation` in a content script — was **validated in the hack phase**: we can fully replace the prompt with our own 3-option dialog, store permanent per-site decisions, and silently decline when the user opted out of being asked. No blockers.
3. **The OS-level dialog ("DuckDuckGo would like to access…") cannot be replaced or re-triggered.** After a system-level denial, calling the request API again is a no-op; the only recovery is deep-linking the user to system Settings. This applies to camera, microphone, and location alike. Our dialog cannot grant the system permission — the request that triggered the recovery dialog is declined, and the grant takes effect from the next request onward.
4. An icon **can** be added to our custom dialog (validated; nice-to-have).
5. iOS 15+ supports mid-session muting (`setMicrophoneCaptureState` / `setCameraCaptureState`) — the page's MediaStream stays "live" but delivers silence/black frames. Not required for v1 (per-session toggles were rejected) but relevant to future work.
6. **SERP edge case (tested, no conflict):** with DDG location set to "always allow", the SERP's "Clear location" control clears the stored SERP value but does not re-trigger the prompt.

---

## 4. Key Decisions of Record

### 4.1 Design Peer Review decisions (https://app.asana.com/1/137249556945/task/1214486639931400)

- **Entry point = browser menu**, not the address bar, not the Privacy Dashboard. Rationale: the dashboard is web-based vs native permissions (Desktop removed permission UI from it), dashboard usage is very low (the menu is opened >30× as often), address-bar icon overload, and permissions are conceptually "website settings" not "privacy controls". A user test validated menu discoverability.
- **No per-session toggles** in the on-site controls (see §2 Out of scope).
- **Accessibility:** never rely on color alone to distinguish "always allowed" from "in use"; an in-use label affordance was agreed.
- **Copy:** the prompt's persistent-grant button is **"Allow While Using Site"** (mirrors Apple's "Allow While Using App"); the picker/settings state for the default remains **"Ask Each Time"**. Match OS button wording per platform.
- **Animation:** simple pop-in/pop-out **built in code — no Lottie**. Prototype: https://www.figma.com/proto/T0iVvA2UkFGnzjk5nSqO1Z/Permission-prototypes?node-id=177-2359
- Pictogram (if shipped before rebrand): existing Lock-Color-24 icon.

### 4.2 Pinned decisions ("Assets and documentation", https://app.asana.com/1/137249556945/task/1214575927044914)

1. Site prompt first, system prompt second (location ordering to be confirmed in implementation — confirmed feasible by the hack phase).
2. Site prompt has 3 options.
3. On-site controls in the menu are shown **only for permanent or active permissions** — never if the site didn't ask.
4. System-Settings link shown in the on-site controls when the user allowed the site but the system permission is denied; the link disappears once the system permission is granted.

### 4.3 Privacy triage decisions — HARD requirements

**Mobile triage (APPROVED by Lucas Adamski, 2026-06-12** — subtask of the design project, GID 1215589903253313**):**

- All permission state is **local device state only**.
- The global default per permission type is **binary: Ask Each Time (default) / Never Allow** — there is **no global "Always Allow"** (matches the Windows triage resolution: default-level setting is Ask/Never only; per-site keeps all three options).
- Per-site Always/Never states are standard prompt outcomes.
- Fire Button clears permissions.

**Desktop precedent triage (APPROVED by Sam Macbeth, 2026-01-21** — https://app.asana.com/1/137249556945/task/1212839269529570 — cited as the model**):**

- **Only explicit persistent choices (Always Allow / Never Allow) are persisted and listed in Settings.** Ephemeral grants (Allow Once) are never persisted and appear only in on-site UI while active.
- **No passive records:** merely being prompted (and defaulting to "ask") must not create a stored or visible record — otherwise the permissions list becomes a subset of browsing history (the key risk scenario: user clears History but a sensitive site remains visible in Settings).
- Permissions are cleared with **"Cookies and site data"** semantics (site data, not history).
- Edge case: a row the user **manually** set back to "Ask Each Time" **may remain listed** — a deliberate interaction, so no surprise exposure.

### 4.4 Other decisions

- The hack-phase finding replaced the originally-designed recovery **toast** with a **reminder dialogue** linking to System Settings (Sveta, 2026-07-06; Figma updated).
- Global "Never Allow" (prevent sites from asking) is enforced by **silently declining** requests — no UI shown at all.
- Reuse macOS permissions code where practical (Brindy/Bartosz 1:1; macOS inspection confirmed partial reusability after removing AppKit coupling; original ~3-week estimate stands).
- Sequencing (Sveta, 2026-06-30, parent problem task): the redesigned tiered prompts must land **before** the on-site permission manager — the manager relies on the redesigned prompts. (This iOS project bundles both; the ordering constrains internal sequencing.)

---

## 5. Functional Requirements

### FR-1: 3-option site permission dialogue

When a website requests camera, microphone, or location and no applicable stored/global decision exists, show DuckDuckGo's own modal dialogue (custom glass alert over a dimmed page; the page stays visible).

- **Buttons, top→bottom, identical for all variants:** `Allow Once` · `Allow While Using Site` · `Never Allow`. All equally weighted (no visual primary).
- **Four variants** (Figma component set 372:7918):

  | Variant | Icon | Title | Body |
  |---|---|---|---|
  | Location | location arrow | `“<domain>” website wants to access your location` | — |
  | Camera | video camera | `“<domain>” website wants to access your camera` | — |
  | Microphone | microphone | `“<domain>” website wants to access the microphone` | — |
  | Location on DDG SERP | DuckDuckGo logo | `“duckduckgo.com” wants to access your location` | `We’ll anonymize your location and use it to deliver better results, closer to you.` |

- Semantics: **Allow Once** = ephemeral grant, never persisted (§4.3); **Allow While Using Site** = persistent per-site allow ("Always Allow" in pickers); **Never Allow** = persistent per-site deny.
- No combined camera+microphone request dialogue is designed (see Open Questions OQ-2).
- Copy note: the main task and older docs say "Always Allow / Allow Once / Never Allow"; **the Figma copy is the source of truth** (peer-review decision).

### FR-2: Dialogue ordering (site first, system second)

- On first grant: DDG site dialogue → *only if* the user chose Allow Once / Allow While Using Site **and** the OS permission is not yet determined → iOS system dialogue → site gets access.
- If the OS permission is already granted, skip the system step (Figma sticky: "Skip if DDG already has device permissions").
- If the user declines the site dialogue, the OS prompt is never triggered — preserving the one-shot OS prompt for later.
- A site-level denial produces no animation and (for Never Allow) a persistent deny.

### FR-3: Applying stored and global decisions

On a permission request, precedence (decided 2026-08-26 — global Never Allow is absolute; see FR-9/OQ-8):

1. **Global default for that type = Never Allow** → silently decline; show nothing.
2. **Stored per-site Never Allow** → decline without prompting.
3. **Stored per-site Always Allow** → grant without prompting **if** the OS permission allows it; if the OS permission is denied, decline and surface the recovery affordances (FR-5).
4. **Active Allow Once grant** (within its validity window) → grant without re-prompting.
5. Otherwise → show the dialogue (FR-1).

### FR-4: On-site permission manager (menu entry + bottom sheet)

- **Menu entry:** a standalone `Site Permissions` row in the browser menu (options/sliders icon), positioned above Add Bookmark (per Figma 380:46904). Shown **only** when the current site has permanent or active permission state (§4.2.3); hidden otherwise. This is a "temporary" list item in the sense that it comes and goes with the site's state.
- **Bottom sheet** (Figma set 442:114704), header `Permissions for “<domain>”` (truncate long domains with ellipsis) + close button. Three states:
  1. **Permissions only:** one row per relevant permission with an inline picker; caption `Reload the page for changes to take effect.`; blue `Remove Permissions` row.
  2. **Permissions + Reminder:** rows, then a group with `Remove Permissions` + `Go to System Settings` (grouped together, per the design), then the reminder footer.
  3. **Reminder only:** just `Go to System Settings` + footer.
- **Row anatomy:** type icon + label (`Location` / `Camera` / `Microphone`) + current state (`Ask Each Time` / `Always Allow` / `Never Allow`) + picker chevrons.
- **Per-site picker options:** `Ask Each Time` / `Always Allow` / `Never Allow`; while an ephemeral grant is active the picker shows `Allow This Time` (checked) / `Always Allow` / `Never Allow` (Figma 870:21926).
- **Icon states (Figma set 443:36250 / 442:113096):** outline = Ask Each Time; outline + blocked badge = Never Allow; solid = Always Allow (not in use); **solid red ("Status-Red": Light `EB102D` / Dark `FF545A`) = currently in use** (applies to both Always and Ask-Each-Time grants). Must also carry a non-color "in use" affordance (accessibility, §4.1); the exact textual/VoiceOver affordance is OQ-14.
- **Reminder footer copy** (multi-permission, dynamic bracketed list): `DuckDuckGo needs to access your camera, [location, and microphone], if you want to use related features on this site.` Single-permission variants exist in two phrasings (see Open Questions OQ-4).
- Changes to a permission that the page is currently using may require a page reload to take effect — hence the caption and the "Reload" step in the recovery flow (Figma flow C).
- `Remove Permissions` resets all of the site's permissions to Ask Each Time, removes the site from the Settings list, and shows toast `Permissions removed for <domain>` with `Undo`.

### FR-5: Recovery from denied system permissions

Two cases (the original toast design was updated by the hack-phase decision):

- **Case A — user allows the site, then denies the OS prompt:** no animation; the on-site sheet gains the System-Settings reminder (see OQ-5 on menu-entry visibility timing). Reminder toasts exist in the design for this moment: `DuckDuckGo couldn’t share location with this site` / `…couldn’t give camera access…` / `…couldn’t give microphone access…` (no action button).
- **Case B — user allows a site's permission but the OS permission was already denied:** show the **reminder dialogue** (Figma set 380:46545): title `DuckDuckGo needs to access your <type>`, body `<Type> permissions are needed if you want to use <type> features on this site.`, buttons `Change Permissions` / `Cancel` (both gray for site variants). `Change Permissions` deep-links to Settings → Apps → DuckDuckGo.
- The System-Settings link in the sheet is shown only when the user allowed the site but the OS denies it, and disappears once the OS permission is granted (§4.2.4).
- Our UI can never grant the OS permission; the triggering request is declined and the grant applies from the next request (§3.3).

### FR-6: Settings > Site Permissions

- **Entry:** a `Site Permissions` row in Main Settings (icon: Website-Permissions-Color-24). Note: Main Settings rows are locale-sorted, so the exact position varies by language; the Figma placement (after "Sync & Backup") is indicative only.
- **Site Permissions page:**
  - Section with global rows `Location`, `Camera`, `Microphone`, each a **2-option picker: Ask Each Time (default) / Never Allow** (§4.3 — this is the "prevent sites from asking" control; it is a picker, not a toggle).
  - Footer: `You can view and modify DuckDuckGo’s system permissions in System Settings.` with "System Settings." as a link to Settings → Apps → DuckDuckGo.
  - **Manage Sites** section (only when at least one site has stored permissions): favicon + domain rows → per-site page; below the list, `Remove All Site Permissions` → toast `Permissions removed for all sites` + `Undo`.
  - Empty state: global pickers + footer only.
- **Per-site page:** nav title = domain; three rows with the 3-option picker; `Remove Permissions` (removes the site from the list, resets to Ask Each Time, toast + Undo).
- **List membership rule (privacy-mandated):** a site appears only after an explicit persistent choice (Always/Never via prompt or manager). Rows manually reset to Ask Each Time **remain listed** until explicitly removed (decided 2026-08-26 — desktop parity, matching the mobile triage's list description). Ephemeral grants never appear here.

### FR-7: Visual feedback & animation

- After a permission is **granted**, show a brief pop-in/pop-out animation (code-built, no Lottie; prototype in §4.1). Figma stickies place it in the browsing chrome immediately after the grant; the main task describes it as "in the menu". Exact placement per prototype (see OQ-6).
- No animation after denial (site-level or system-level).
- Status iconography per FR-4 across the sheet and settings.
- Note from peer review: once granted, the iOS system status-bar indicators (green/orange dots) are the signal users actually notice — our animation complements, not replaces, them.

### FR-8: Fire Button, fireproofing, and data lifecycle

- **Fire Button** (and auto-clear, which shares the same pipeline): clears **all stored site permissions except fireproofed sites**. Success criteria call this "Fire Button integration".
- **Manual removal in Settings** (`Remove All Site Permissions` / per-site `Remove Permissions`): removes **everything, including fireproofed sites**.
- Permissions clear under **"Cookies and site data"** semantics, never tied to History (§4.3).
- Stored permission data must remain clearable by the Fire Button even if the feature is later disabled or rolled back — clearing must not depend on the feature flag.
- Verification note: the mobile triage approval summary says "Fire clears all permissions" without mentioning the fireproofing exemption; the exemption matches Desktop behavior and the documented project scope, but should be confirmed at privacy review (OQ-7).

### FR-9: Global "prevent sites from asking"

- Setting any type's global default to Never Allow silently declines all requests of that type with no dialog (validated in the hack phase for location).
- **Global Never Allow is absolute** (decided 2026-08-26, resolving OQ-8): it silently declines requests even for sites with a stored Always Allow. Per-site rows remain stored and editable in Settings but are inert until the global default returns to Ask Each Time. To be confirmed with design.

---

## 6. Copy Inventory (Figma = source of truth)

Prompt and picker copy is in §5. Additional strings:

- Toasts: `Permissions removed for all sites` (+Undo) · `Permissions removed for <domain>` (+Undo) · `DuckDuckGo couldn’t share location with this site` · `DuckDuckGo couldn’t give camera access to this site` · `DuckDuckGo couldn’t give microphone access to this site`
- Reminder dialogues: `DuckDuckGo needs to access your location/camera/microphone` / `<Type> permissions are needed if you want to use <type> features on this site.` / `Change Permissions` / `Cancel`
- Sheet: `Permissions for “<domain>”` · `Reload the page for changes to take effect.` · `Remove Permissions` · `Go to System Settings`
- Settings: `Site Permissions` · `Manage Sites` · `Remove All Site Permissions` · `You can view and modify DuckDuckGo’s system permissions in System Settings.` · `Permissions for <domain>`
- Alternate single-permission footers: `DuckDuckGo needs access to this device location/camera/microphone, if you want to use <type> features on this site.` (competing phrasing — OQ-4)
- App-feature reminder variants exist in Figma (Voice Search / Duck.ai Voice Chat, with blue-primary `Change Permissions`) — owned by other projects; do not regress them.

Copy-review goals (from the copy task, 1214494688509116): align our dialogue structure with the system dialogues that follow; align the Settings list with the dialogues; keep terminology consistent within the platform.

## 7. Assets

- Icons (dub.duckduckgo.com/duckduckgo/Icons): Website-Permissions-Color-24 (Settings); Location-24 / Location-Blocked-24 / Location-Solid-24; Microphone-24 / -Blocked / -Solid; Video-24-1 / Video-Blocked-24 / Video-Solid-24; Info-Recolorable-24 (accent); Bell-24 (unused in v1 scope).
- Color: "Status-Red" — Light `EB102D`, Dark `FF545A`.
- Dark mode is fully designed (Figma 443:37697); iOS 26 / Liquid Glass styling; SF Pro.

## 8. Non-functional Requirements

- **Accessibility:** state never conveyed by color alone; "in use" needs a textual/label affordance; standard VoiceOver support for dialogs, pickers, sheet rows.
- **Localization:** all new strings localized through the standard pipeline; long-domain truncation must hold across locales.
- **Privacy:** §4.3 requirements are hard; additionally, analytics must never include domains/hostnames (Desktop permission pixels set the precedent: type + decision only).
- **No regressions** to existing special flows: Duck.ai microphone handling, voice search, SERP location behavior (§3.6).
- **Rollout safety:** feature must be gateable for staged rollout to 100% of iOS users.

## 9. Measurement & Instrumentation

New pixels needed (naming per Desktop precedent — type + decision only, no domains):

- Prompt shown / decision taken per type (allow-once / allow-always / never).
- Permission manager (sheet) opened; state changed (from → to, per type); permissions removed (per-site, all-sites).
- Settings page opened; global default changed.
- System-Settings link/dialog interactions (reminder shown, Change Permissions tapped).
- Friction signal (parent KPI): manager opened + change attempted but not completed.

## 10. Open Questions & Unresolved Items

| # | Item | Source |
|---|---|---|
| OQ-1 | "Question to engineers — can we show a system dialogue directly instead?" of the next-visit reminder dialogue (recovery Case B) — partially resolved by design: the OS prompt is requested directly whenever its state is notDetermined; the reminder dialogue applies only when the OS permission is denied. Confirm with design | Figma sticky, flow D |
| OQ-2 | Combined camera+microphone request: no combined dialogue is designed; multi-permission copy flagged TODO. Decide: two sequential dialogs vs new combined design. **Must be resolved before the dialog PR** | Figma TODO sticky |
| OQ-3 | "Copy for multiple denied location" and the mixed state (running permissions + system-denied reminder simultaneously) — copy TODO | Figma TODO sticky |
| OQ-4 | Two competing footer phrasings ("needs to access your X" vs "needs access to this device X"); minor title inconsistencies ("the microphone" vs "your camera/location"; DDG variant drops "website"); "Reload the page…" with/without period. Resolve with copy review — **needed before the dialog/geolocation PRs** | Figma inconsistencies |
| OQ-5 | Menu-entry visibility immediately after site-allow + system-deny: one sticky says "No Site Permissions entry in the menu", yet the recovery sub-flow opens the sheet (reminder-only state) from the menu. Clarify when the entry appears in this state | Figma flow D |
| OQ-6 | Exact placement/target of the grant animation (browsing chrome vs menu button) — annotated ("Show animation") but never visually specified; follow the prototype | Figma + peer review |
| OQ-7 | Confirm the fireproofing exemption on Fire-Button clearing with privacy (mobile triage summary said "Fire clears all permissions" without addressing fireproofing) | §5 FR-8 |
| OQ-8 | **Resolved 2026-08-26: global Never Allow is absolute** — declines even sites with stored Always Allow; per-site rows stay stored/editable but inert (confirm with design) | gap → decided |
| OQ-9 | Exact validity window of "Allow Once" on iOS. The definition must cover: page reload, SPA/same-host navigation, redirects, tab close, web-content-process termination, app termination, and restored tabs. Desktop distinguishes "until reload" vs "until tab closes"; the iOS design only says "Allow Once"/"Allow This Time" | gap vs Desktop triage |
| OQ-10 | Behavior in Fire-mode tabs (ephemeral browsing): do stored permissions apply, and are decisions made there ever persisted? | gap |
| OQ-11 | Whether permission changes can apply without reload in some cases (mid-session muting exists per §3.5); v1 assumes reload (caption + flow C "Reload" sticky), re-evaluate in a real build | peer review |
| OQ-12 | Per-site settings page header shows literal `Permissions for site.com` under a real-domain nav title (likely a placeholder oversight) | Figma |
| OQ-13 | When is a persistent "Allow While Using Site" committed relative to a subsequent OS-prompt denial, and what stored decision remains — this determines whether the menu entry/recovery sheet is reachable (ties to OQ-5) | independent review |
| OQ-14 | Exact textual/VoiceOver affordance for "currently in use" (a non-color signal is required by §4.1) | independent review |
| OQ-15 | UX when the OS permission is `restricted` or unavailable (MDM, parental controls, missing hardware) — System Settings cannot fix it, so a "Change Permissions" route would be unusable | independent review |
| OQ-16 | Precise definition of the "manager change attempted but not completed" friction pixel, measurable without recording domains | independent review |

## 11. Design & Evidence Index

- Figma full flow (iOS): https://www.figma.com/design/aMaDTBcE9Fsfu40NbjzcrH/Permission--iOS-Android-?node-id=380-46782
- Figma components / all copy (iOS): https://www.figma.com/design/aMaDTBcE9Fsfu40NbjzcrH/Permission--iOS-Android-?node-id=380-46764
- Dialogue copy set: …?node-id=372-7918 · List-item variants: …?node-id=443-36250 · System-Settings message variants: …?node-id=442-113695
- Animation prototype: https://www.figma.com/proto/T0iVvA2UkFGnzjk5nSqO1Z/Permission-prototypes?node-id=177-2359
- Design project: https://app.asana.com/1/137249556945/task/1213825194381340 · Pinned assets & decisions: https://app.asana.com/1/137249556945/task/1214575927044914
- Privacy triages: mobile (approved; design-project task GID 1215589903253313) · desktop precedent https://app.asana.com/1/137249556945/task/1212839269529570
- Tech input: https://app.asana.com/0/1214732727456025/1214732727456025
- Problem tasks: https://app.asana.com/1/137249556945/task/1212343625229910 (iOS prompt handling) · https://app.asana.com/1/137249556945/task/1213911423943411 (Permission Prompt Experience)
