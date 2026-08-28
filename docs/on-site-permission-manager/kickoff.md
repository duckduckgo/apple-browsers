# Kick-off: Per site permission manager (iOS)

Copy-paste body for the Asana kick-off task. Full context: [requirements.md](requirements.md), [tech-design.md](tech-design.md).

---

Zoom link: <Zoom link> (confirm)

Stakeholders and their responsibilities
Project Advisor: @Brindy
Other stakeholders: @Sveta (design) @David (copy) @Chris Thelwell

Scope updates
- Duck.ai stays an explicit exception to the whole model in both flag states (decided; ratify in item 12).
- Fire Button integration moved into PR 1 so persisted data always has a burn path.
- Platform-precedents review complete (platform-precedents.md): several defaults revised to match shipped macOS/Android behavior (items 1, 3, 4, 9); Android's tiered prompt and on-site manager are absent from the inspected develop checkout; the privacy-test-pages fixtures already exist.
- v1 is iOS-standalone: no macOS changes, no shared Permissions package. Convergence deferred until there's proven reusable behavior.
- Implementation lives in one new local package (`iOS/LocalPackages/SitePermissions`) plus thin app glue.
- Hack phase is done (geolocation interception validated). No new hack phase needed.
- Address-bar indicator and post-grant banner stay descoped (menu entry point instead, per design peer review).

Discussion items

1/ Confirm that **Always Allow** overrides the global **Never Allow** setting

The global setting stops new permission prompts. It does not block a site that the user already allowed.
Android uses this rule. macOS uses a similar rule for video autoplay: it evaluates the per-site decision before the global policy.
[Bartosz, recommended] Confirm this behavior.

2/ Approve the combined camera and microphone dialog copy before PR 3

WebKit handles camera and microphone together, so iOS needs one combined dialog.
macOS and Android also use one combined dialog:

- [macOS] **Allow “site” to use your camera and microphone once?**
- [Android] A combined title with a **Remember** checkbox.

Open: Write and approve the three-option copy for this dialog.
Owner: @Sveta @David, before PR 3.

3/ Confirm when **Allow Once** ends

**Allow Once** stays in memory for the current page. It ends:

- when the page reloads.
- after any navigation except same-document navigation.
- when the tab closes.
- when WebKit replaces the web content process. This happens when the page's renderer crashes or iOS evicts it under memory pressure; the page then behaves as if it reloaded.
- when the app process terminates. Backgrounding alone does not end the grant. A background kill ends it because the grant exists only in memory.

iOS does not save or restore this grant. It does not use Android's 24-hour grant.
[Bartosz, recommended] Confirm this behavior.

4/ Confirm what happens when the user allows a site but denies the iOS permission

Keep the site's **Always Allow** decision. Do not change it to **Never Allow**.
Show the **Site Permissions** menu item and the reminder in the sheet.
Android changes the site decision to **Never Allow**. iOS will not.
Open for @Sveta: Update the Figma note that says to hide the menu item in this state.

5/ Approve the remaining copy before PR 3

Open:

- Choose between "access your X" and "access to this device X" for the footer.
- Make the camera and microphone titles consistent.
- Write copy for multiple denied permissions.
- Write copy for a state with active permissions and a system reminder.
- Confirm the per-site header. The design shows **Permissions for site.com**.

Owner: @David @Sveta.

6/ Confirm where to show the grant animation

The design notes call for an animation, but the design does not show its location.
[Bartosz, recommended] Follow the prototype. Confirm whether the animation appears in the browser chrome or on the menu button.

7/ Define accessible states for permissions that are in use or muted

Color alone cannot show that a permission is in use. Define the visible label and VoiceOver text.
Also define the `.muted` state. In this state, the site keeps the stream but receives silence or black video.
Open: Show this state as red **In Use**, as paused, or as another state.
Owner: @Sveta @David.

8/ Define the reminder for permissions that the user cannot change

This includes restrictions from device management, parental controls, or missing hardware.
System Settings cannot fix these states, so do not show **Change Permissions**.
[Bartosz, recommended] Show the reminder without the **Change Permissions** button. Use copy that explains the restriction.

9/ Confirm how permissions work in fire-mode tabs

Fire-mode tabs read saved site decisions and global defaults. They do not save new decisions.
Grants last only for the current session.
macOS Burner tabs read and write saved decisions. iOS fire-mode tabs only read them.
Fire mode is temporary, so iOS does not save new decisions there.
[Bartosz, recommended] Confirm this behavior.

10/ Confirm privacy behavior before PR 1

Confirm these points:

- The Fire Button keeps permissions for fireproofed sites. Manual removal still deletes these permissions.
- The Fire Button and **Remove All** delete only saved site records. They keep the global defaults.
- Permission keys use only the host. They ignore the scheme and port.
- Platform security checks still limit grants to secure contexts.

The mobile triage summary says, “Fire clears all permissions,” but it does not mention fireproofed sites.
The platform review supports these points.
We will follow macOS: remove a leading `www.` from the host. Android keeps it.
Confirm with privacy: 0.25d

11/ Define the incomplete-change friction pixel

The parent KPI needs a signal when a user opens the manager but does not complete a change.
The pixel must not record domains. Neither macOS nor Android measures this today.
Candidate events:

- manager opened.
- edit started.
- edit saved.
- manager closed with an unsaved change.
- permission removed or restored with Undo.
- reminder shown.
- **Settings** selected.

12/ Confirm the remaining decisions

- If the system permission state is `notDetermined`, show the OS prompt directly.
- If the system permission is already denied, show the reminder dialog.
- A per-site deny or **Remove Permissions** stops active capture immediately.
- Grants and other changes apply after a reload or new request.
- Both Duck.ai permission call sites keep the current microphone behavior. This applies with the feature flag on or off.
- The global **Never Allow** setting does not apply to Duck.ai.
- Android also treats the Duck.ai microphone as an exception.
- Temporary grants do not create rows in Settings. The privacy review calls for this difference from macOS and Android.
- If the site has no newer record, Undo restores the deleted record.
- Undo does not restore **Allow Once** grants.

13/ Show **Site Permissions** for a site with only an **Ask Each Time** record?

Settings already lists the site. The current menu rule refers to a permanent or active permission state.
[Bartosz, recommended] Show the menu item for any saved record or active permission. This includes an **Ask Each Time** record.

14/ Decide which permissions to show in the on-site sheet

[Bartosz, recommended] Show a row for a saved record or an active permission. Also show permissions requested during the current visit.
Do not add a row only because the global setting is **Never Allow**.
Owner: @Sveta.

15/ Include the updated Voice Search denied-permission prompt (@Sveta's ask)

Feasible: the prompt is our own alert, not the OS prompt, so it works after an OS denial — it explains the problem and deep-links to Settings. The app already ships a plain version (`NoMicPermissionAlert`: title, message, Settings, Cancel); this restyles it to the new reminder design (**Change Permissions** / **Hide Voice Search** / **Cancel**).
[Bartosz, recommended] Yes — fold into PR 3, which builds the same reminder-dialog component: ~0.5d.
Note: iOS can never re-show the OS microphone prompt after a denial. When the OS state is notDetermined, the microphone button triggers the OS prompt directly.

Next steps
Rebase the branch on main (~31 commits behind): @Bartosz 0.1d
Replace old implementation subtasks with the 6-PR plan: @Bartosz 0.25d
Privacy confirmations (item 10): @Bartosz 0.25d — before PR 1
Feature Flags Registry entry + PR 1 (flag, assets, package, store, Fire): @Bartosz 3d
Combined-dialog and copy decisions (items 2, 5–8): @Sveta @David before PR 3
