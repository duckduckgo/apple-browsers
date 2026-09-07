# [iOS] On-site permission manager

Author: Bartosz

Reviewer: @Brindy (confirm)

Stakeholders: @Chris Thelwell, @Sveta, @David

Project: [[iOS] On-site permission manager and updated permission dialogues](https://app.asana.com/1/137249556945/task/1213800892997347)

## Background & Requirements

The iOS browser does not have a site-permission model. For camera and microphone, WebKit shows its own per-page prompt, and the browser does not see or store the result. WebKit handles location without an iOS delegate hook.

The project adds browser-managed permissions for camera, microphone, and location. Users can make persistent decisions for each site, grant temporary access, manage saved decisions, and recover from system-level denial. The [requirements](requirements.md) define the expected product behavior and UI.

macOS already has a permission manager, but its implementation is not portable. Its public interfaces expose Core Data identity, macOS-only types, and extension points designed for the macOS app. Only a few small model types are directly reusable.

## Problem Statement

Design an iOS permission system that gives users persistent, visible, and reversible control for each site without coupling the implementation to macOS-specific architecture.

## Recommended Approach

1. **Create one internal Swift Package Manager package for iOS.**

   Add `iOS/LocalPackages/SitePermissions`. The package contains:

   - The permission types and decisions.
   - The store that reads and writes decisions.
   - One permission coordinator for each browser tab.
   - A Swift wrapper around the Apple permission APIs.
   - The geolocation user script and native location provider.
   - Reusable permission dialogs and the on-site permission sheet.

   The iOS app connects the package to WebKit, Settings, browser menus, and the Fire Button.[1]

   Use the same persisted raw values as macOS. This choice keeps future code sharing possible without changing macOS in version 1.

2. **Store the version 1 data in `UserDefaults` through the repository's typed storage layer.**

   Create a concrete `@MainActor` `SitePermissionsStore`. The app injects `UserDefaults.app` through `KeyedStoring`, which is the repository's type-safe wrapper for key-value storage.

   Use one key for all site decisions and a different key for the three global defaults. This split lets Fire clear site decisions without changing the global defaults.[2]

   Store only explicit persistent decisions. Do not store **Allow Once** grants or a record that only shows that a prompt occurred. Each site can store at most three short decisions, one for each permission type.

3. **Give each browser tab one permission coordinator.**

   Create one `SitePermissionsCoordinator` for each tab. It has four responsibilities:

   - **Resolve each request in a defined order.** A stored site decision takes precedence over the global setting. An iOS system denial can still block a stored site allow.
   - **Queue permission dialogs.** If several requests arrive together, show one dialog at a time. Do not reject a request only because another permission dialog is visible.
   - **Track page-scoped decisions.** Keep **Allow Once** and a one-time denial in memory for the current page.
   - **Discard results for old pages.** Camera, microphone, and location requests can finish after a navigation. Before applying a result, check that the original tab and page still exist. If they do not, discard the result.

   The coordinator resolves a request in this order:

   1. Preserve the Duck.ai exception.
   2. Apply a stored site denial.
   3. Apply a stored site allow, subject to iOS system permission.
   4. Apply an active **Allow Once** grant.
   5. Apply the global **Never Allow** setting.
   6. Otherwise, show the site-permission dialog.

   The coordinator uses its own dialog queue and shows dialogs in the order that requests arrive. The existing JavaScript alert presenter does not queue requests.[3]

4. **Add a small Swift wrapper around the Apple permission APIs.**

   Create a `SystemPermissionClient`. This small Swift type:

   - Reads camera and microphone authorization through `AVCaptureDevice`.
   - Requests camera and microphone authorization.
   - Reads and requests location authorization through `CLLocationManager`.
   - Gets location updates.
   - Refreshes authorization state after the app returns from the background.

   Use one `CLLocationManager` for authorization and location delivery. This keeps both operations on the same view of the iOS authorization state.[4]

5. **Use WebKit's native media hook and add a geolocation user script.**

   Handle camera and microphone through `WKUIDelegate`. WebKit provides this native callback on iOS.

   WebKit does not provide an equivalent public iOS callback for `navigator.geolocation`. Inject a user script when each document starts. The script intercepts `navigator.geolocation` and `permissions.query`. The second API lets a page ask for the current permission state.

   The user script does not decide whether to grant access. It performs these steps:

   1. Receive a geolocation call from the page.
   2. Send a request identifier to Swift.
   3. Wait while the coordinator and `SystemPermissionClient` apply the browser and iOS permission rules.
   4. Return a location or an error to the page.

   The request flow is:

   `Website → user script → SitePermissionsCoordinator → SystemPermissionClient → CLLocationManager → iOS`

   Native Swift code derives the site identity and communicates with iOS. The page cannot select its own stored permission key or call `CLLocationManager` directly.[5]

6. **Define where the geolocation user script runs.**

   Inject the script into the top-level document and document iframes. The top-level document is the page shown in the address bar. An iframe is an HTML document embedded in that page.

   Injection into an iframe means that the browser can see its request and apply security checks. It does not mean that every iframe receives location. Deny location requests from cross-site iframes.

   A `WKUserScript` does not run inside web workers or service workers. These are background JavaScript contexts, not HTML documents. Version 1 does not change `permissions.query` inside those contexts. This is a limited gap because workers do not expose the normal `navigator.geolocation` API.[6]

7. **Store each decision against the top-level site.**

   Derive the stored permission key from the current top-level page in native code. This is the page whose URL appears in the address bar. Do not accept a site key from JavaScript.

   Keep the requesting iframe's origin as separate information. Use it only for WebKit security checks. An iframe must not replace or own the decision that belongs to its top-level page.[7]

   Normalize the stored key as follows:

   - Remove a leading `www.`.
   - Convert an internationalized domain to its ASCII punycode form.
   - Ignore the URL scheme and port.

   Use the registrable domain, also called eTLD+1, only for the fireproof-site check. For example, the eTLD+1 of `maps.example.com` is `example.com`. Keep permission decisions specific to the normalized host.

8. **Implement the agreed permission behavior in the coordinator and store.**

   The [requirements](requirements.md) remain the source of truth. The following decisions affect the architecture:

   - A stored site allow overrides the global **Never Allow** setting. The global setting prevents new prompts but does not override stored choices.
   - **Allow Once** stays in memory for the current page and is never persisted.
   - An iOS denial does not rewrite the user's stored site choice.
   - Fire-mode tabs can read stored choices but cannot write them.
   - An explicit denial or removal stops active permission use. Grants and other changes apply on the next request or reload.
   - Duck.ai remains outside the new permission model and keeps its existing behavior.

## Notes

[1] **Package alternatives:** Extracting a shared package from macOS requires an API redesign because the existing interfaces expose macOS-specific dependencies. Reusing the macOS store and manager also imports macOS lifecycle rules. Keeping all code in the iOS app target is possible, but it makes the feature boundary less clear and removes package-level tests.

[2] **Storage alternatives and size:** The stored map should remain small because only explicit persistent choices create records. The number of sites has no fixed limit, and each update writes the complete map. `UserDefaults` is acceptable for version 1 as a small, reversible choice. The store does not access it directly. If real usage makes the map large, replace the storage dependency with a dedicated `KeyValueFileStore`. Core Data is not justified unless the feature later needs large datasets, queries, relationships, or migrations.

[3] **Why the JavaScript alert presenter cannot be reused:** The current presenter handles website calls to `alert()`, `confirm()`, and `prompt()`. If another modal or JavaScript alert is visible, it completes a new alert immediately instead of waiting. A confirmation returns `false`, and a text prompt returns `nil`. Reusing this behavior for permissions would silently reject a second request. Permission dialogs therefore need their own queue.

[4] **Coordinator and system-client alternatives:** One app-wide coordinator cannot represent page-scoped grants. Separate coordinators for each permission type would divide one request across several owners. Separate location managers can observe authorization changes at different times. One coordinator per tab and one location manager keep ownership clear.

[5] **Geolocation implementation alternatives:** The app already uses the remote `content-scope-scripts` package. It provides injected browser and privacy features such as Global Privacy Control, Email Protection, and autofill. Its current Apple implementation has no geolocation feature. Its messaging also does not identify the requesting frame. Adding geolocation there needs a separate repository change and release.

macOS uses a private WebKit geolocation API that is not available on iOS. A dedicated iOS user script keeps version 1 self-contained. Move the script to `content-scope-scripts` later if its behavior stabilizes and another platform can reuse it.

[6] **Worker scope:** The main gap is Permissions API parity. The geolocation user script can replace page and iframe behavior because WebKit injects scripts into those documents. WebKit does not inject the same script into worker contexts.

[7] **Site-key alternatives:** Keying by the requesting iframe would let embedded content own the top-level site's saved decision. Trusting a JavaScript-supplied host would make untrusted input part of a security boundary. Storing by eTLD+1 would make permissions apply to more hosts than the agreed model.

## Testing

Test the architecture at three levels:

- **Package tests:** Check storage, request order, page-scoped decisions, and Fire-mode read-only behavior. Check that queued dialogs appear one at a time. Check that the coordinator discards results for a closed or navigated page.
- **App regression tests:** Preserve the existing camera and microphone behavior, including the Duck.ai exception.
- **WebKit integration tests:** Check geolocation and `permissions.query` in the top-level page and iframes. Cover secure contexts, sandboxed frames, Permissions Policy, cross-site iframe denial, navigation, and recovery after an iOS denial.

Also test these storage and deletion cases:

- Fire clears site decisions but preserves global defaults.
- Fire preserves decisions for fireproofed sites.
- **Allow Once** and a prompt without a persistent choice create no stored record.
- A representative large site map remains within an acceptable read and write time.

## Additional Considerations

### Privacy

The [mobile privacy triage](https://app.asana.com/1/137249556945/task/1215589903253313) is approved. Store only explicit persistent choices. Do not store a record only because a prompt occurred. Permission keys contain only the normalized host, and pixels must not contain domains. Fire and manual removal clear site decisions while preserving global defaults.

### Security

Native navigation state supplies the top-level site identity. JavaScript supplies request identifiers, not permission keys. A stored permission does not bypass WebKit restrictions. The request must use HTTPS. The iframe sandbox must allow the request. The top-level page must delegate the permission to an iframe through Permissions Policy.

### Site Breakage

The geolocation user script replaces part of a Web API and is the main compatibility risk. Limit version 1 to document contexts. Preserve WebKit security behavior. Validate the user script against the existing privacy test pages.

### Experimentation

The architectural decisions do not require an A/B test. Validate the geolocation implementation with integration tests and a staged rollout.

### Operational

The design requires no infrastructure or deployment changes and no new SLI or SLO. The Fire worker provides the deletion path for stored site decisions.

### Localization / Internationalization

The package uses the standard localization pipeline. UI copy and layout remain part of the product requirements and design review.
