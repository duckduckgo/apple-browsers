# Kick-off: Per site permission manager (iOS)

Copy-paste body for the Asana kick-off task. Full context: [requirements.md](requirements.md), [tech-design.md](tech-design.md).

---

Zoom link: <Zoom link> (confirm)

Stakeholders and their responsibilities
Project Advisor: @Brindy
Other stakeholders: @Sveta (design) @David (copy) @Chris Thelwell

Scope updates
- Re-planned delivery after three design reviews: 6 stacked PRs, one subtask per PR, ~21–25d total. The old implementation subtasks will be replaced.
- Duck.ai stays an explicit exception to the whole model in both flag states (decided; ratify in item 12).
- Fire Button integration moved into PR 1 so persisted data always has a burn path.
- v1 is iOS-standalone: no macOS changes, no shared Permissions package. Convergence deferred until there's proven reusable behavior.
- Implementation lives in one new local package (`iOS/LocalPackages/SitePermissions`) plus thin app glue.
- Hack phase is done (geolocation interception validated). No new hack phase needed.
- Address-bar indicator and post-grant banner stay descoped (menu entry point instead, per design peer review).

Discussion items

1/ Global "Never Allow" beats per-site "Always Allow" (decided — ratify)
Global Never silently declines all requests of that type. Per-site rows stay stored and editable, but inert.
[Bartosz, recommended] Keep as decided. Simplest model; Figma shows no exception UI.
Alternative: Chrome-style — per-site Always overrides global Never.

2/ Combined camera+microphone request — blocks the dialog PR (PR 3)
One WebKit decision covers both permissions; no combined dialog is designed.
Options:
[Bartosz, recommended] One combined dialog variant (needs design + copy)
Two sequential dialogs
Resolve with Sveta before PR 3, or timebox a design decision: 0.25d

3/ What ends "Allow Once"?
Must be defined for: reload, SPA/same-host navigation, redirects, tab close, app termination, restored tabs.
[Bartosz, recommended] Per tab+site; ends on leaving the site or closing the tab; survives reload. (Desktop uses "until reload".)

4/ Site allowed, then OS prompt denied — Figma is contradictory
One sticky says no menu entry appears; the recovery flow opens the sheet from the menu. Also unresolved: is the site "allow" committed before the OS answer?
[Bartosz, recommended] Commit the site decision at choice time; menu entry appears; sheet shows the reminder state.

5/ Copy gaps — needed before PR 3
Footer phrasing ("access your X" vs "access to this device X"), mic/camera title inconsistency, multi-denied copy, mixed granted+reminder state, per-site header placeholder ("Permissions for site.com").
Owner: @David + @Sveta.

6/ Grant animation placement
Stickies say "show animation"; no frame shows where.
[Bartosz, recommended] Follow the prototype; confirm the target (browser chrome vs menu button).

7/ "In use" needs a non-color affordance; `.muted` state undefined
The red icon alone fails accessibility. Exact label/VoiceOver text undefined.
Also: how does a muted capture (`.muted` state — page holds the stream, delivers silence/black) appear — red "in use", paused, or something else?
Owner: @Sveta + @David.

8/ OS permission restricted or unavailable (MDM, parental controls, no hardware)
System Settings can't fix these, so "Change Permissions" would dead-end.
[Bartosz, recommended] Show the reminder without the Settings button, with plain copy.

9/ Fire-mode tabs
[Bartosz, recommended] Session-only: fire-mode tabs never read or write stored permissions.

10/ Privacy confirmations — needed before PR 1
Three items to confirm together:
- Fire keeps fireproofed sites' permissions; manual removal clears everything. The mobile triage summary said "Fire clears all permissions" without addressing fireproofing.
- Fire and Remove All clear per-site records only; global defaults are preserved.
- The permission key is host-only (scheme and port collapsed); grants stay secure-context-only via platform gating.
Confirm with privacy: 0.25d

11/ Friction pixel: "opened manager, attempted a change, didn't complete it"
Parent KPI needs it. Define precisely, without recording domains.

12/ Ratify decided defaults
- The OS prompt is shown directly whenever its state is notDetermined; the reminder dialogue appears only when the OS permission is already denied.
- Mid-session permission changes (Remove Permissions, global Never) apply on reload/next request, not mid-capture; re-evaluate in a real build.
- Duck.ai is an explicit exception: both call sites keep today's mic behavior in both flag states; global Never doesn't apply to duck.ai.
- Fire-mode tabs never read or write per-site records but still obey global defaults.
- Undo restores only the deleted record, only if the site has no newer record; never restores Allow Once grants.

13/ Does an explicit-Ask-only site show the menu entry?
The site is listed in Settings; the menu rule says "permanent or active" state.
[Bartosz, recommended] Yes — any stored record or active state shows the entry.

14/ Which rows appear in the on-site sheet?
Stored, active, requested-this-visit, and globally-denied permissions produce different row sets.
[Bartosz, recommended] Rows for permissions that are stored, active, or were requested this visit; globally-denied types add no row.
Owner: @Sveta.

Next steps
Rebase the branch on main (~31 commits behind): @Bartosz 0.1d
Replace old implementation subtasks with the 6-PR plan: @Bartosz 0.25d
Privacy confirmations (item 10): @Bartosz 0.25d — before PR 1
Feature Flags Registry entry + PR 1 (flag, assets, package, store, Fire): @Bartosz 3d
Combined-dialog and copy decisions (items 2, 5–8): @Sveta @David before PR 3
