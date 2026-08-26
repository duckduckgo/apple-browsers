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
- Platform-precedents review complete (platform-precedents.md): several defaults revised to match shipped macOS/Android behavior (items 1, 3, 4, 9); Android's tiered prompt and on-site manager are absent from the inspected develop checkout; the privacy-test-pages fixtures already exist.
- v1 is iOS-standalone: no macOS changes, no shared Permissions package. Convergence deferred until there's proven reusable behavior.
- Implementation lives in one new local package (`iOS/LocalPackages/SitePermissions`) plus thin app glue.
- Hack phase is done (geolocation interception validated). No new hack phase needed.
- Address-bar indicator and post-grant banner stay descoped (menu entry point instead, per design peer review).

Discussion items

1/ Global "Never Allow" vs per-site "Always Allow" (decided — ratify)
Revised after the platform review: a stored per-site Always Allow overrides global Never; the global control only prevents asking. Matches Android's shipped predicate and macOS's autoplay precedent.
[Bartosz, recommended] Ratify the platform-aligned rule.

2/ Combined camera+microphone request — copy blocks the dialog PR (PR 3)
One WebKit decision covers both permissions. Both shipped platforms confirm a single combined dialog (macOS: "Allow "site" to use your camera and microphone once?"; Android: combined title + Remember checkbox).
Remaining: the 3-option copy for the combined variant.
Owner: @Sveta @David, before PR 3.

3/ What ends "Allow Once"? (decided — ratify)
macOS model adopted: in-memory and page-scoped — ends on reload and any non-same-document navigation, tab close, process replacement, and app termination; never persisted or restored. Explicitly not Android's persisted 24-hour grant.
[Bartosz, recommended] Ratify.

4/ Site allowed, then OS prompt denied (decided — ratify; one Figma contradiction open)
Decided: the site allow commits at choice time; an OS denial never converts it to Never Allow (Android does the opposite — deliberate divergence); the menu entry appears and the sheet shows the reminder state.
Open for @Sveta: the Figma sticky claiming no menu entry appears in this state.

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

9/ Fire-mode tabs (decided — ratify)
Android model adopted: fire-mode tabs read stored decisions and global defaults but never write; grants there are session-only. (macOS burner tabs read and write the shared store — rejected as unfit for an ephemeral mode.)

10/ Privacy confirmations — needed before PR 1
Three items to confirm together:
- Fire keeps fireproofed sites' permissions; manual removal clears everything. The mobile triage summary said "Fire clears all permissions" without addressing fireproofing.
- Fire and Remove All clear per-site records only; global defaults are preserved.
- The permission key is host-only (scheme and port collapsed); grants stay secure-context-only via platform gating.
The platform review confirms all three: both platforms exempt fireproofed sites from Fire, clear per-site rows only, and keep global controls untouched. macOS also drops `www.`; Android keeps it — we follow macOS.
Confirm with privacy: 0.25d

11/ Friction pixel: "opened manager, attempted a change, didn't complete it"
Parent KPI needs it. Define precisely, without recording domains. Neither platform measures this today. Candidate events: manager open, edit begun, edit committed, dismissal with dirty state, remove/undo, reminder shown, Settings tap.

12/ Ratify decided defaults
- The OS prompt is shown directly whenever its state is notDetermined; the reminder dialogue appears only when the OS permission is already denied.
- An explicit per-site deny or Remove Permissions revokes active capture immediately (macOS model); grants and other changes apply on reload/next request.
- Duck.ai is an explicit exception: both call sites keep today's mic behavior in both flag states; global Never doesn't apply to duck.ai. (Android similarly special-cases Duck.ai microphone.)
- Temporary grants never create Settings rows — a deliberate, privacy-triage-mandated divergence from both shipped platforms.
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
