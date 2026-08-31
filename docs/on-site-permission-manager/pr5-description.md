# Suggested PR title

`Add on-site geolocation permission flows`

# Suggested PR body

Task/Issue URL: https://app.asana.com/1/137249556945/task/1217863452475662
Tech Design URL: https://app.asana.com/1/137249556945/task/1213800892997347
CC:

### Description

Adds website geolocation to DuckDuckGo's on-site permission flow. It includes a page-world `navigator.geolocation` shim, native frame attribution, one-shot and watch routing, the shared Core Location provider, location-specific dialogs and recovery, and the DuckDuckGo search-results variant.

The feature remains behind `sitePermissions`, which is off by default. With the flag off, new pages use WebKit's existing geolocation behavior. A page that was already loaded while the flag was on keeps its injected shim until its next navigation; the retained handler resolves outstanding calls safely during that interval.

### Testing Steps

1. Run `xcodebuildmcp simulator build --project-path iOS/DuckDuckGo-iOS.xcodeproj --scheme "iOS Browser" --simulator-id 2DBE9D9D-B0E5-4B7D-B3C8-8975E2E5C9F1`. The app builds with the normal project deployment target.
2. Run `SitePermissionsTests`, the selected app permission-routing and content-blocking tests, `WebViewUnitTests`, and the shared `UserContentControllerTests`. The verified runs pass 319 tests with no failures or skips: 165 + 36 + 109 + 9. Simulator tests use the test-only `IPHONEOS_DEPLOYMENT_TARGET=16.0` override required by unrelated current-main test code.
3. The 35-test geolocation script subset is included in the package total above. It covers real `WKWebView` policy and lifecycle behavior, including sandbox-attribute removal, dynamic policy re-sampling, and late-result denial.
4. Enable `sitePermissions` and load an HTTPS top-level page that calls `navigator.permissions.query({ name: "geolocation" })`, `getCurrentPosition`, and `watchPosition`. The query and request agree, the DuckDuckGo site prompt appears before iOS asks for location, valid positions reach the correct callbacks, and `clearWatch` stops further callbacks.
5. Repeat the request from an exact same-origin iframe. It follows the top-level permission model. Repeat from same-site cross-origin and cross-site iframes, including one with `allow="geolocation"`. Both cross-origin cases return `PERMISSION_DENIED`, report `denied` from `query`, and show no prompt.
6. Repeat from an insecure, sandboxed, or synthetic frame. Then load a top-level response with `Permissions-Policy: geolocation=()`. Each case returns `PERMISSION_DENIED`, reports `denied`, and shows no prompt.
7. Allow a location request, exercise Allow Once, Allow While Using Site, and Never Allow, and then deny the iOS prompt. Site choices persist according to the selected scope, and an iOS denial produces the location recovery flow without changing the site choice.
8. Run the companion `privacy-test-pages` fixtures from local branch `bartosz/on-site-permissions-5` at commits `d91ba2b` and `f330b4f2`. The full fixture lint passes, and the local header-deny smoke test returns HTTP 200 with `Permissions-Policy: geolocation=()`.

### Impact

High. This change mediates privacy-sensitive website access to the user's location and replaces WebKit's geolocation entry point while the feature is enabled.

#### What could go wrong?

- A cross-origin or synthetic frame could inherit a top-level grant → every request is attributed from `WKScriptMessage.frameInfo.securityOrigin`; native code rejects mismatched, empty, opaque, and insecure origins, while the shim rejects sandboxed and synthetic contexts.
- A page-level policy could be ignored → the main-frame `Permissions-Policy` response header is captured during provisional navigation and promoted only on commit. The shim also honors the browser's policy API when one is available.
- A forged or stale message could reach Core Location → bridge messages require a private capability, a per-frame nonce, the original web view and native frame identity, and a current navigation and process generation.
- A failed navigation could break the surviving page → each new request refreshes native frame registration, and failed provisional navigation restores the prior committed page policy.
- A watch could survive navigation, process replacement, or data clearing → all three paths cancel provider work, remove native registrations, and reject late callbacks.
- An invalid or stale Core Location fix could reach the page → invalid coordinates and negative accuracy are discarded, one-shots respect `maximumAge` and `timeout`, and batches use the newest valid fix.
- A deallocated reply target could leave a page promise pending → the permanent shared message handler now always supplies an error reply when its weak target is unavailable.

### Quality Considerations

- V1 uses one best-effort implementation on every supported iOS version. It does not depend on an unreleased OS API and uses no private WebKit API.
- Top-level documents and exact same-origin iframes follow the normal permission model. All cross-origin iframes are denied in v1, including same-site and explicitly delegated frames. This is intentionally stricter than a full browser engine.
- Main-frame response headers are parsed only for the `geolocation` directive. An explicit exclusion applies to the entire committed page.
- Permission storage remains keyed by the committed top-level host. Requesting-frame origins are used only for native policy gating and never come from JavaScript payloads.
- Location management rows, `PermissionStatus` change events, and geolocation pixels remain deferred to Phase 6.
- Worker and service-worker parity remains out of scope because the app has no worker injection route.
- The SERP copy and the broader location copy still require copy review.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
