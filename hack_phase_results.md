# Geolocation Permissions — Hack Phase Results

**Branch:** `bartosz/on-site-permissions-geo-hack`
**Goal:** Validate whether iOS web **geolocation** permission can be brought under our control — i.e. replace WebKit's built‑in "this site wants to know your location" prompt with our own dialog — by intercepting `navigator.geolocation` in an injected content script. Camera/microphone already have a public WebKit delegate hook and are out of scope for the hack; geolocation is the hard case, so the spike focused there.

> ⚠️ This is throwaway spike code. It builds and runs, but it is **not** production quality and must not be merged. It exists to answer feasibility questions before we commit an estimate.

---

## TL;DR

**The approach works. Verdict: YES — viable to build on.**

Intercepting `navigator.geolocation` in a document‑start content script reliably replaces WebKit's native web geolocation prompt with our own UI on iOS. All three JS entry points (`getCurrentPosition`, `watchPosition`, `clearWatch`) work through the shim against a real `CLLocationManager`, and the returned coordinates matched stock behaviour on `main`. Crucially, **WebKit's own per‑site prompt no longer appears** — our dialog takes its place.

The only genuine "no" is a platform limitation that is **not specific to this approach**: the **OS‑level** CoreLocation authorization prompt is system‑owned — we can't restyle it, can't add an icon to it, and can't re‑show it after the user denies it (Settings deep‑link only). That constraint exists regardless of how we implement web permissions.

---

## The two‑layer permission model (key to reading everything below)

There are **two independent permission layers**, and separating them resolves almost every question:

| Layer | Who owns it | Prompt | Can we control it? |
|---|---|---|---|
| **1. OS CoreLocation authorization** (does the *app* get location at all) | iOS | System 3‑option sheet: *Allow Once / Allow While Using App / Don't Allow* | **No.** Can't restyle, can't add icon, can't re‑prompt after denial (Settings only). Shown once per app. |
| **2. Per‑site web permission** (does *this website* get location) | Normally WebKit (its web prompt) | WebKit's "site wants your location" | **Yes — this is what the hack takes over.** Our dialog, our options, our storage, our re‑prompt rules. |

The hack moves layer 2 from WebKit to us. Layer 1 is untouched and behaves like any CoreLocation app.

---

## What was built

All spike code lives in **two existing files** (no `.xcodeproj`/pbxproj changes, so it builds without project surgery):

- **`iOS/DuckDuckGo/UserScripts.swift`**
  - `GeolocationUserScript` — injected at `document-start`, **all frames**, in the **page content world** (`requiresRunInPageContentWorld = true`). Running in the page world is what makes the `navigator.geolocation` override visible to page scripts and puts the message handler in the same world.
  - The JS **shim**: replaces `navigator.geolocation.{getCurrentPosition,watchPosition,clearWatch}`, and mirrors `navigator.permissions.query({name:'geolocation'})` so the Permissions API stays consistent with our decision.
  - `WebGeolocationProvider` — a per‑tab `CLLocationManager` wrapper: authorization, `maximumAge` caching, `timeout`, `enableHighAccuracy`, W3C error codes, and fan‑out of one manager to concurrent one‑shots + watches.
- **`iOS/DuckDuckGo/TabViewController.swift`**
  - `GeolocationUserScriptDelegate` conformance: a placeholder allow/deny dialog (per‑origin in‑memory cache + prompt coalescing) that drives the provider and pushes results back into the originating frame.

**Bridge:** JS→native via `webkit.messageHandlers.geolocation.postMessage`; native→JS via `evaluateJavaScript(_:in:in:.page)` targeting the originating frame, calling a `window.__ddgGeoDispatch` dispatcher. One mechanism serves one‑shot resolves, continuous watch updates, and Permissions‑API state changes.

`Info.plist` already contained `NSLocationWhenInUseUsageDescription`, so no plist change was needed.

---

## How it was tested

- Ran the **iOS Browser** scheme on simulator/device.
- Test page: `privacy-test-pages/features/permission-prompts.html` (location card: *Request (once)*, *Watch*, *Stop*, *Check state*, plus live State / Coords rows). State is driven by `navigator.permissions.query`; Coords by `navigator.geolocation`.
- Compared side‑by‑side against `main`.

**Observed flow on `main`:** tap *Request (once)* → OS CoreLocation sheet → then **WebKit's own** "'localhost' would like to use your current location" prompt → State `granted`, coords shown.

**Observed flow on the branch:** tap *Request (once)* → **our** "Location access" dialog → OS CoreLocation sheet → coords shown. **WebKit's own per‑site prompt never appeared** — it was replaced by our dialog. After the Permissions‑API fix (below), State also flips to `granted` live.

---

## Results against the validation questions

| # | Question | Result |
|---|---|---|
| 1 | Intercept `navigator.geolocation` via content script? | ✅ **Validated** (built + tested) |
| 2 | Suppress WebKit's own web geolocation prompt? | ✅ **Validated** — it no longer appears |
| 3 | Replace 2‑option flow with a custom 3‑option dialog (always / this time / never)? | ✅ **Feasible** — we fully own the dialog |
| 4 | Store permanent per‑site permissions (always allow/deny) in Settings/Permissions? | ✅ **Feasible** — plumbing validated; persistence + UI is build work |
| 5 | Let users opt out of all location dialogs ("Don't allow to ask")? | ✅ **Feasible** — we control whether any dialog shows |
| 6 | *(nice‑to‑have)* Add an icon to the iOS **system** alert? | ⚠️ **Split:** No for the OS sheet; **Yes** for our own dialog |
| 7 | Re‑prompt the **system** dialog after the user tapped "Don't Allow"? | ❌ **Not possible** for the OS sheet — Settings deep‑link only (our per‑site prompt *can* be re‑shown) |

### 1 & 2 — Interception and prompt suppression ✅
The override installs before any page script (document‑start, page world), in the main frame and iframes, and re‑installs on every navigation; same‑document history changes keep the same context so the override persists. Because page scripts hit **our** object, WebKit's native geolocation code path — and therefore its web prompt — is never invoked. Confirmed on device: WebKit's "site would like to use your location" prompt is gone; our dialog replaces it. `getCurrentPosition`, `watchPosition` (continuous), and `clearWatch` all behave correctly, including `enableHighAccuracy`, `timeout`, `maximumAge`, and the permission‑denied / position‑unavailable / timeout error codes. Coordinates matched `main`.

### 3 — Custom 3‑option dialog ✅
The decision is made entirely in native code — WebKit only ever sees the final outcome. The spike shows a placeholder 2‑button `UIAlertController`, but nothing constrains it: swapping in a 3‑option dialog (**Always allow / Allow this time / Never allow**) is purely UI + how we record the choice. Mapping to behaviour:
- **Allow this time** → grant for the session; re‑ask next session.
- **Always allow** → persist grant.
- **Never allow** → persist deny; auto‑reject future requests with no dialog.

All three are our own state on top of `getCurrentPosition`; WebKit is not involved.

### 4 — Persistent per‑site permissions ✅ (plumbing proven)
The spike caches decisions per origin (in‑memory, per tab) and does **not** re‑prompt on repeat — proving the store→decision→no‑reprompt loop. For production this becomes a real per‑site store. Note iOS currently has **no** per‑site permission store; macOS has `PermissionManager`/`PermissionStore` which can be ported. **Important finding:** the store must also back `navigator.permissions.query` (see below), so a persisted "always allow" drives both the geolocation flow *and* the Permissions API consistently.

Caveat (layer split): a persisted **"always allow"** still only yields coordinates if the **app** has OS location authorization. If OS location is off, even an always‑allowed site fails — that's the Settings‑recovery case (#7).

### 5 — Global "don't ask" opt‑out ✅
Because we decide whether any dialog is shown, a per‑site or global "Don't allow to ask for permission" is trivial: skip the dialog and immediately resolve to the stored default (typically deny → `PERMISSION_DENIED`) with **zero** prompts and no WebKit prompt leak. Validated that the no‑dialog deny path returns the correct `GeolocationPositionError` and shows nothing.

### 6 — Icon on the alert ⚠️ (nice‑to‑have, assessed, not built)
- **OS CoreLocation sheet:** **not customizable** — no icon, no custom buttons; it's system UI.
- **Our dialog:** **yes** — since the whole point of the hack is that *we* render the per‑site permission UI (replacing WebKit's), we can put any icon/branding on it. This is trivial with a custom SwiftUI/UIKit view (like the existing `WebJSAlert`); `UIAlertController` itself has no supported icon API, so a custom view is the way. Not implemented in the spike.

### 7 — Re‑prompt the system dialog after denial ❌ / recovery ✅ (assessed, not built)
Once the user denies **OS** location (or it's off in Settings), `requestWhenInUseAuthorization()` is a no‑op — iOS will not re‑show the system sheet. The only recovery is deep‑linking to Settings (`UIApplication.openSettingsURLString`) from a toast/dialog and letting the user flip the toggle. The app already uses this pattern for microphone (`NoMicPermissionAlert`, which has a Settings button); the same applies here. This limits **layer 1 only** — our **per‑site** "Never allow" is our own state and can be surfaced/changed/re‑prompted freely in‑app.

---

## API‑fidelity note surfaced by testing (the "State" bug)

During testing, `State` (from `navigator.permissions.query`) stayed `prompt` even after granting, while coords worked. Root cause: the shim initially overrode only `navigator.geolocation`, not `navigator.permissions.query` — so the Permissions API never reflected the grant. On `main`, WebKit backs both surfaces from one store, so it stays in sync automatically.

**Fix (applied):** the shim now mirrors `navigator.permissions.query({name:'geolocation'})` — it reads the native per‑origin state and fires `PermissionStatus.onchange` when the user allows/denies, so `State` tracks the decision live (matching `main`).

**Production takeaway:** a JS‑shim approach must own **both** `navigator.geolocation` **and** `navigator.permissions.query` (geolocation entry), wired to the same permission store. Missing the Permissions API is an easy way to break real sites that gate on it.

---

## Failure modes & caveats found

1. **Security:** the message handler is registered in the **page** content world, so page JS could call `webkit.messageHandlers.geolocation.postMessage` directly and spoof requests. Fine for a spike; **must** be closed for production (see below).
2. **Non‑HTTP(S) / synthetic frames:** `about:blank` / `srcdoc` / `javascript:` iframes are historically flaky for document‑start injection in WebKit. Some such frames may not get the shim — needs an explicit decision.
3. **`isSecureContext`:** the spike exposes `navigator.geolocation` even on insecure origins (WebKit wouldn't). Production should gate on secure context.
4. **W3C object identity:** results are plain objects shaped like `GeolocationPosition`/`…Error` (right fields + error constants) but are not real class instances (`instanceof` fails). Fine for ~all real sites; noted.
5. **bfcache:** on back‑forward restore, JS watches can look alive while native ones were stopped on `pagehide`. Edge case; needs robust lifecycle handling.
6. **Per‑tab `CLLocationManager`:** the spike uses one per tab (wasteful at scale). Production should use a single shared manager.

---

## Recommended production approach

- **Move the shim into content‑scope‑scripts** using the existing `messageSecret` handshake + `UserScriptMessageBroker`/`Subfeature` pattern (as `favicon`/`printing` do). This is the correct home and closes the spoofing gap (#1).
- **Own both JS surfaces:** `navigator.geolocation` **and** `navigator.permissions.query` (geolocation), backed by one store.
- **Per‑site permission store + Settings UI:** port the macOS `PermissionManager`/`PermissionStore` model to iOS (none exists there today); support *Always allow / Allow this time / Never allow* and a per‑site/global "Don't ask". Reuse this for camera/mic so all three permission types share one model and one Settings surface.
- **Custom dialog** (SwiftUI, mirroring `WebJSAlert`) with the 3 options — and an app/site **icon** here (satisfies the nice‑to‑have for the part we control).
- **Single shared `CLLocationManager`** with proper lifecycle + accuracy handling.
- **OS‑denial recovery:** a toast/dialog that deep‑links to Settings (the `NoMicPermissionAlert` pattern) — this is the only lever for layer 1.
- Decide policy on `isSecureContext` gating and `about:blank`/`srcdoc` frames.

**Primary production risk:** the model rests on the shim being un‑bypassable and WebKit's native prompt staying suppressed across all frame types and future iOS releases — this is undocumented/private territory, so it needs solid automated coverage. Everything observed so far supports feasibility.

---

## Notes for camera & microphone (context, not part of the geolocation hack)

Camera/mic do **not** need this hack — WebKit exposes `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` on iOS. The app can show its own 3‑option dialog and call `decisionHandler(.grant/.deny)`; "allow this time" vs "always allow" is again just our persistence choice. So the 3‑option flow is achievable for all three types — via the delegate for camera/mic, via the JS shim for geolocation — ideally sharing one permission store and one dialog component.

---

## Appendix — where things are

| Piece | Location |
|---|---|
| Content script + JS shim, CoreLocation provider | `iOS/DuckDuckGo/UserScripts.swift` (`GeolocationUserScript`, `WebGeolocationProvider`, `GEOLOCATION SPIKE` section) |
| Custom dialog + delegate wiring | `iOS/DuckDuckGo/TabViewController.swift` (`extension TabViewController: GeolocationUserScriptDelegate`) |
| Location usage string | `iOS/DuckDuckGo/Info.plist` → `NSLocationWhenInUseUsageDescription` (already present) |
| Test page | `privacy-test-pages/features/permission-prompts.html` |

**Run:** open the **iOS Browser** scheme → run on simulator/device → load `permission-prompts.html` (simulator: set **Features ▸ Location ▸ Custom Location…** first, or fixes will time out) → exercise the Location card and compare against `main`.
