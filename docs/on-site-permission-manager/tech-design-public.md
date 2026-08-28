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

   Add `iOS/LocalPackages/SitePermissions`. The package owns the permission model, persisted state, request coordination, system-permission client, geolocation provider, and reusable permission UI. The iOS app target owns WebKit routing, Settings and menu registration, Fire Button integration, and other app-only effects.[1]

   Keep the small persisted model compatible with macOS by using the same raw values. This preserves a path to future convergence without making macOS changes part of version 1.

2. **Use simple local persistence and one coordinator per tab.**

   Use a concrete `@MainActor` store over `KeyedStoring`. Store site decisions and global defaults under separate keys so that site data can be cleared without changing global preferences.[2]

   Give each tab one concrete `SitePermissionsCoordinator`. It owns decision precedence, page-scoped grants, prompt serialization, and stale-request rejection. A small injected system client owns camera, microphone, and location authorization. It uses one `CLLocationManager` for both authorization and location delivery.[3]

3. **Use the native media hook and an app-owned geolocation bridge.**

   Handle camera and microphone through `WKUIDelegate`. Handle location through a WebKit user script backed by the native system client.[4]

   The bridge intercepts `navigator.geolocation` and `permissions.query`. Version 1 supports the main frame and document iframes. Worker and service-worker support is out of scope because iOS provides no injection route for those contexts.

4. **Key decisions by the top-level site.**

   Derive the permission key from the committed top-level page in native code. Do not accept a host from JavaScript. Keep the requesting frame's origin separate so that the bridge can enforce secure-context, sandbox, and Permissions Policy rules.[5]

   Normalize the key as a host: remove a leading `www.`, use the punycode form for internationalized domains, and collapse the scheme and port. Use eTLD+1 only to check whether Fire should preserve a fireproofed site. Deny location requests from cross-site iframes.

5. **Implement the agreed permission behavior in the coordinator and store.**

   The [requirements](requirements.md) remain the source of truth. The following decisions have direct architectural impact:

   - A stored site allow overrides the global **Never Allow** setting. The global setting prevents new prompts but does not override stored choices.
   - **Allow Once** stays in memory for the current page and is never persisted.
   - An OS denial does not rewrite the user's stored site choice.
   - Fire-mode tabs can read stored choices but cannot write them.
   - An explicit denial or removal stops active permission use. Grants and other changes apply on the next request or reload.
   - Duck.ai remains outside the new permission model and keeps its existing behavior.

## Notes

[1] **Alternatives:** Extracting a shared package from macOS would require redesigning APIs that expose macOS-specific dependencies. Reusing the macOS store and manager would also import macOS lifecycle assumptions. Keeping all code in the iOS app target is viable, but it provides less isolation and makes the feature boundary harder to maintain.

[2] **Alternatives:** Core Data is not justified for a small property-list map that does not need queries, relationships, or migrations. A separate actor or store protocol would add a boundary without a current consumer that needs it.

[3] **Alternatives:** An app-wide coordinator cannot represent page-scoped grants safely. Separate per-permission coordinators or a separate decision engine would divide one request flow across multiple owners. Separate location managers can observe different authorization states. The existing JavaScript alert path cannot serialize permission prompts because it declines new alerts while another alert is visible.

[4] **Alternatives:** The current content-scope-scripts dependency has no Apple geolocation feature, and its message path does not identify the requesting frame. Supporting it would require a separate repository change and release. The private macOS WebKit geolocation API is not available on iOS. A JavaScript-only implementation cannot own trusted site identity or system authorization. The shim is also iOS-only — Android and macOS intercept geolocation natively — and its semantics are provisional, so v1 wants same-PR iteration behind our own flag. The JS is one self-contained file behind a message contract: we migrate it into content-scope-scripts once the semantics stabilize and either its messaging gains frame context or a second platform needs the shim.

[5] **Alternatives:** Keying by the requesting frame would let an embedded frame own the top-level site's saved decision. Trusting a JavaScript-supplied host would move a security boundary into untrusted input. Storing by eTLD+1 would make permission decisions broader than the agreed host-level scope.

## Testing

Test the architecture at three levels:

- Package tests cover persistence, decision precedence, page-scoped grants, prompt serialization, stale callbacks, and Fire-mode behavior.
- App regression tests preserve existing media behavior, including the Duck.ai exception.
- WebKit integration tests cover geolocation, the Permissions API, iframe attribution, secure contexts, Permissions Policy, cross-site iframe denial, navigation, and OS-denial recovery.

Also verify that Fire clears site decisions, preserves global defaults, and respects fireproofed sites.

## Additional Considerations

### Privacy

The [mobile privacy triage](https://app.asana.com/1/137249556945/task/1215589903253313) is approved. The store contains only explicit persistent choices. Permission keys contain only the normalized host, and pixels must not contain domains. Fire and manual removal clear site decisions while preserving global defaults.

### Security

Native navigation state supplies the top-level site identity. JavaScript supplies request identifiers, not permission keys. Stored permission never bypasses WebKit restrictions for insecure contexts, sandboxed frames, or iframes without Permissions Policy delegation.

### Site Breakage

The geolocation bridge is the main compatibility risk because it replaces part of a Web API. Limit version 1 to supported window contexts, keep WebKit security behavior intact, and validate the bridge against existing privacy test pages.

### Experimentation

The architectural decisions do not require an A/B test. Validate the geolocation bridge with integration tests and a staged rollout.

### Operational

The design requires no infrastructure or deployment changes and no new SLI or SLO. The Fire worker provides the recovery path for persisted browsing data.

### Localization / Internationalization

The architecture uses the standard package localization pipeline. UI copy and layout behavior remain part of the product requirements and design review.
