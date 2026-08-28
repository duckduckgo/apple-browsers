# Tech design (Asana-ready body): [iOS] On-site permission manager

Paste everything below into the tech-design subtask. Deeper detail lives in the repo on branch `bartosz/on-site-permissions`, in `docs/on-site-permission-manager/` (requirements.md, tech-design.md, platform-precedents.md).

---

Author: Bartosz
Reviewer: @Brindy (confirm)
Stakeholders: @Chris Thelwell @Sveta @David
Project: [iOS] On-site permission manager and updated permission dialogues — https://app.asana.com/1/137249556945/task/1213800892997347

Background & Requirements

Today the iOS browser has no site-permission model. For camera and microphone, our WKUIDelegate returns `.prompt`, so WebKit shows its own two-option, per-page alert and we never see or store the outcome. For geolocation, WebKit handles everything itself — we have no hook at all. The iOS system prompt is one-shot: a single "Don't Allow" locks the whole app out of that permission for every website, and users have no way to discover or reverse it. This drives real breakage (id.me: 173 reports in 3 months, more than 60% iOS).

The project adds, for camera, microphone, and location: a 3-option site prompt (Allow Once / Allow While Using Site / Never Allow) shown *before* the system prompt, persistent per-site decisions, an on-site manager in the browser menu, a Settings > Site Permissions page with global "prevent asking" controls, a recovery path to system Settings after an OS-level denial, and Fire Button integration. Everything ships behind one remote-releasable flag (`sitePermissions`, default off). Detailed requirements, exact copy, and open questions live in `docs/on-site-permission-manager/requirements.md` in the repo.

Problem Statement

Give iOS users persistent, discoverable, and reversible control over camera, microphone, and location for individual websites — without changing today's shipped behavior while the feature flag is off.

Recommended Approach

Build the feature iOS-standalone, in one new internal Swift package, independent of the macOS implementation.

1. Add the `sitePermissions` feature flag and the one missing icon asset. With the flag off, every current code path runs verbatim.
2. Create `iOS/LocalPackages/SitePermissions` (one production target, one test target). At a high level it contains four pieces[1]:
   - a small permission model (type, tri-state decision, per-site record);
   - a `@MainActor` store over `KeyedStoring`, with the per-site map and the global defaults under separate keys;
   - a per-tab decision coordinator with its own prompt queue;
   - a system-permission client (AVCaptureDevice plus one shared CLLocationManager driver).
   The same PR registers the app-side Fire worker, so persisted data always has a burn path: it clears per-site records, exempts fireproofed sites, preserves global defaults, and runs even when the flag is off.
3. Camera and microphone: route `requestMediaCapturePermissionFor` through the coordinator behind the flag. Show the 3-option dialog first; trigger the OS prompt only after a positive choice. Duck.ai keeps its existing special-case behavior in both flag states. The same phase restyles the existing Voice Search denied-microphone alert to the new reminder design (also behind the flag).
4. Geolocation: intercept `navigator.geolocation` and `permissions.query` with a user script in the page content world (validated in the hack phase), backed by a native CLLocationManager provider. v1 covers window contexts in the main frame and document iframes; workers have no injection route and stay out of scope. Cross-site iframes are denied.
5. Management surfaces: a Settings entry with global 2-option pickers and a Manage Sites list, plus a per-site bottom sheet reachable from the browser menu when the site has stored or active permission state. Users can remove one site or all sites, with Undo.
6. Recovery: when the OS permission is already denied, show a reminder dialog that deep-links to Settings → Apps → DuckDuckGo. The site-level decision commits at choice time; an OS denial never rewrites it.

Key semantics — aligned with shipped macOS and Android behavior after a code-level review of both (`platform-precedents.md`), and ratified at the 2026-08-28 kick-off:

- A stored per-site Always Allow overrides the global Never Allow default; the global control only prevents asking[2].
- Allow Once lives in memory for the current page. It ends on reload or navigation and is never persisted.
- An explicit deny or removal revokes active capture immediately. Grants apply on reload or the next request.
- Fire-mode tabs read stored decisions but never write.
- Only explicit persistent choices create Settings rows — a privacy-triage rule, and a deliberate divergence from both platforms.

Delivery is a 6-PR stack, each PR releasable with the flag off; ~21–25 person-days.

Notes

[1] The model duplicates three small enums from macOS instead of sharing code. Raw values stay byte-identical to macOS's, so a future shared package remains cheap.

[2] This matches Android's shipped predicate and macOS's autoplay precedent; it reversed an earlier "global Never is absolute" draft decision.

Alternatives considered and rejected:

- **Extract the macOS permission model into a shared package.** Only the type and decision enums are directly portable. The macOS store and manager leak Core Data identity (`NSManagedObjectID`), macOS-only types (`FireproofDomains`, `TLD`), and an override seam through their public surface. Extraction is an API redesign, not a move, and it puts shipped, unflagged macOS behavior at risk before iOS ships anything. We defer convergence until both platforms have demonstrably reusable behavior.
- **Reuse macOS's per-tab `PermissionModel` and UI.** Built around AppKit popovers and a two-option prompt with different persistence semantics; not portable.
- **Put the iOS code in the app target instead of a package.** Viable — synchronized buildable folders avoid per-file project edits — but the package gives isolation and package-level tests. This choice is reversible.
- **Build the geolocation shim on content-scope-scripts.** Requires a change and release in the external C-S-S repo, and its messaging push path has no originating-frame context. A dedicated user script is self-contained; we can revisit C-S-S later.
- **Core Data persistence.** Overkill for a tiny per-site map; `KeyedStoring` matches existing iOS per-domain features (text zoom, fireproofing).

Testing

- Package unit tests, run through the app scheme in CI: decision precedence, Allow Once lifecycle, store round-trip and Undo semantics, Fire worker fireproofing and eTLD+1 cases, fire-mode read-only behavior.
- Regression tests that freeze today's WKUIDelegate behavior at both call sites (including Duck.ai and camera-only cases) before any routing change.
- Geolocation integration tests against the existing privacy-test-pages fixtures (geolocation, Permissions API, iframe permissions), extended with combined-request, Allow Once lifecycle, and OS-denied recovery cases.
- Flag rollback tests: turning the flag off must restore legacy behavior on the next navigation, with no shim injected into new page loads.

Additional Considerations

Privacy
- Approved mobile privacy triage: https://app.asana.com/1/137249556945/task/1215589903253313. Three implementation details are pinged for the record: Fire exempts fireproofed sites; Fire and Remove All clear per-site records only and preserve global defaults; the permission key is host-only. Only explicit persistent choices create visible records; pixels never contain domains.

Security
- The permission key derives natively from the top-level frame's security origin — never from shim-supplied JavaScript. Platform gating is preserved: no grant in insecure contexts, sandboxed frames, or iframes not delegated by Permissions Policy; cross-site iframe geolocation is denied.

Site Breakage
- The geolocation shim is the main risk because it replaces a platform API surface. Mitigations: a scoped v1 (main frame and document iframes; no workers), a full `permissions.query` transition table, fixtures in privacy-test-pages, and the flag as a kill switch (disabling takes effect on the next page load).

Experimentation
- Rollout uses the remote-releasable flag: internal → percentage ramp → 100%. Prompt-volume and manager-engagement pixels are the interim success signal per the project's success criteria; no A/B cohort is planned.

Operational
- No infrastructure changes. Rollback = flag off; the Fire worker still clears any stored data afterwards.

Localization / Internationalization
- All strings ship in the package through the standard localization pipeline (26 locales already flow into existing packages). Long domains truncate in dialog and sheet titles. The Settings entry position follows locale-sorted ordering, so it varies by language.
