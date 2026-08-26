# Tech design (Asana-ready body): [iOS] On-site permission manager

Paste everything below into the tech-design subtask. Deeper detail lives in the repo on branch `bartosz/on-site-permissions`: `docs/on-site-permission-manager/` (requirements.md, tech-design.md, platform-precedents.md).

---

Author: Bartosz
Reviewer: @Brindy (confirm)
Stakeholders: @Chris Thelwell @Sveta @David
Project: [iOS] On-site permission manager and updated permission dialogues — https://app.asana.com/1/137249556945/task/1213800892997347

Background & Requirements

Today the iOS browser has no site-permission model. For camera and microphone, our WKUIDelegate returns `.prompt`, so WebKit shows its own two-option, per-page alert and we never see or store the outcome. For geolocation, WebKit handles everything itself — we have no hook at all. The iOS system prompt is one-shot: a single "Don't Allow" locks the whole app out of that permission for every website, and users have no way to discover or reverse it. This drives real breakage (id.me: 173 reports in 3 months, >60% iOS).

The project adds, for camera, microphone, and location: a 3-option site prompt (Allow Once / Allow While Using Site / Never Allow) shown *before* the system prompt, persistent per-site decisions, an on-site manager in the browser menu, a Settings > Site Permissions page with global "prevent asking" controls, a recovery path to system Settings after an OS-level denial, and Fire Button integration. Everything ships behind one remote-releasable flag (`sitePermissions`, default off). Detailed requirements, exact copy, and open questions: `docs/on-site-permission-manager/requirements.md` in the repo.

Problem Statement

Give iOS users persistent, discoverable, and reversible control over camera, microphone, and location for individual websites — without regressing today's shipped behavior while the feature flag is off.

Recommended Approach

Build the feature iOS-standalone, in one new internal Swift package, independent of the macOS implementation.

1. Add the `sitePermissions` feature flag and the one missing icon asset. Flag off, every current code path runs verbatim.
2. Create `iOS/LocalPackages/SitePermissions` (one production target + one test target) containing: a small permission model[1], a `@MainActor` store over `KeyedStoring` (per-site map and global defaults under separate keys), a per-tab decision coordinator with its own prompt queue, and a system-permission client (AVCaptureDevice + one shared CLLocationManager driver). Register the app-side Fire worker in the same PR, so persisted data always has a burn path — it clears per-site records (fireproofed sites exempt), preserves global defaults, and runs even when the flag is off.
3. Camera/mic: route `requestMediaCapturePermissionFor` through the coordinator behind the flag; show the 3-option dialog first and trigger the OS prompt only after a positive choice. Duck.ai keeps its existing special-case behavior in both flag states.
4. Geolocation: intercept `navigator.geolocation` and `permissions.query` with a user script in the page content world (validated in the hack phase), backed by a native CLLocationManager provider. v1 scope is window contexts in the main frame and document iframes; workers have no injection route and are out of scope. Cross-site iframes are denied outright.
5. Management surfaces: a locale-sorted Settings entry with global 2-option pickers and a Manage Sites list; a per-site bottom sheet reachable from both browser menus, shown only when the site has stored or active permission state; remove one/all with Undo.
6. Recovery: when the OS permission is already denied, show a reminder dialog that deep-links to Settings → Apps → DuckDuckGo; the site-level decision commits at choice time and is never rewritten by an OS denial.

Key semantics, aligned with shipped platforms after a code-level review of macOS and Android (`platform-precedents.md`): a stored per-site Always Allow overrides the global Never default (the global control only prevents asking)[2]; Allow Once is in-memory and page-scoped (ends on reload/navigation, never persisted); an explicit deny or removal revokes active capture immediately; fire-mode tabs read stored decisions but never write; only explicit persistent choices create Settings rows (privacy-triage rule — a deliberate divergence from both platforms).

Delivery is a 6-PR stack, each releasable with the flag off; ~21–25 person-days.

Notes

[1] The model duplicates three small enums from macOS instead of sharing code. Raw values are byte-identical to macOS's, so a future shared package stays cheap.

[2] This matches Android's shipped predicate and macOS's autoplay precedent; it reversed an earlier "global Never is absolute" draft decision.

Alternatives considered and rejected:

- **Extract the macOS permission model into a shared package.** Only the type/decision enums are directly portable. The macOS store and manager leak Core Data identity (`NSManagedObjectID`), macOS-only types (`FireproofDomains`, `TLD`), and an override seam through their public surface — extraction is an API redesign, not a move, and it puts shipped, unflagged macOS behavior at risk before iOS ships anything. Convergence is deferred until there is demonstrated reusable behavior.
- **Reuse macOS's per-tab `PermissionModel` and UI.** Built around AppKit popovers and a two-option prompt with different persistence semantics; not portable.
- **Put iOS code in the app target instead of a package.** Viable (synchronized buildable folders make per-file project edits unnecessary); the package was chosen for isolation and package-level tests. Reversible.
- **Build the geolocation shim on content-scope-scripts.** Requires a change and release in the external C-S-S repo, and its messaging push path has no originating-frame context. A dedicated user script is self-contained; revisit C-S-S later.
- **Core Data persistence.** Overkill for a tiny per-site map; `KeyedStoring` matches existing iOS per-domain features (text zoom, fireproofing).

Testing

- Package unit tests (run via the app scheme in CI): decision precedence, Allow Once lifecycle, store round-trip and Undo semantics, Fire worker fireproofing/eTLD+1 cases, fire-mode read-only behavior.
- Regression tests freezing today's WKUIDelegate matrices (both call sites, including Duck.ai and camera-only cases) before any routing change.
- Geolocation integration tests against the existing privacy-test-pages fixtures (geolocation, Permissions API, iframe permissions), extended with combined-request, Allow Once lifecycle, and OS-denied recovery cases.
- Flag rollback tests: flag ON→OFF must restore legacy behavior on the next navigation, with no shim injected into new page loads.

Additional Considerations

Privacy
- Approved mobile privacy triage: https://app.asana.com/1/137249556945/task/1215589903253313. Three implementation details pinged for confirmation: Fire exempts fireproofed sites; Fire/Remove All clear per-site records only (global defaults preserved); the permission key is host-only. Only explicit persistent choices create visible records; pixels never contain domains.

Security
- The permission key derives natively from the top-level frame's security origin — never from shim-supplied JavaScript. Platform gating is preserved: no grant in insecure contexts, sandboxed frames, or iframes not delegated by Permissions Policy; cross-site iframe geolocation is denied.

Site Breakage
- The geolocation shim is the main risk: it replaces a platform API surface. Mitigations: scoped v1 (main frame + document iframes; no workers), a full `permissions.query` transition table, fixtures in privacy-test-pages, and the flag as a kill switch (disable takes effect on next page load).

Experimentation
- Rollout via the remote-releasable flag: internal → percentage ramp → 100%. Prompt-volume and manager-engagement pixels are the interim success signal per the project's success criteria; no A/B cohort is planned.

Operational
- No infrastructure changes. Rollback = flag off; the Fire worker still clears any stored data afterwards.

Localization / Internationalization
- All strings ship in the package with the standard localization pipeline (26 locales already flow into existing packages). Long domains truncate in dialog and sheet titles; the Settings entry position follows locale-sorted ordering, so it varies by language.
