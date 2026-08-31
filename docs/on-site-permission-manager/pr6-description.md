# Suggested PR title

`Complete on-site permission management`

# Suggested PR body

Task/Issue URL: https://app.asana.com/1/137249556945/task/1217863452475663
Tech Design URL: https://app.asana.com/1/137249556945/task/1213800892997347
CC:

### Description

Completes the on-site permission manager. It adds Location to the on-site sheet and Settings, keeps page permission status objects up to date, enables the approved geolocation flow pixels, stops active location watches after denial or removal, and hardens concurrent tabs, Fire browsing, and feature rollback.

The feature remains behind `sitePermissions`, which is off by default. Turning the flag off removes the geolocation shim from the next loaded document. A document that was already loaded while the flag was on keeps one coherent permission path until reload or navigation.

### Testing Steps

1. Run `xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"`. The app builds with the normal project deployment target.
2. Run `xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args=-only-testing:UnitTests --extra-args=-only-testing:SitePermissionsTests --extra-args=-only-testing:WebViewUnitTests --extra-args=IPHONEOS_DEPLOYMENT_TARGET=16.0`. The verified run passes 6,928 tests with no failures and 37 baseline skips.
3. Enable `sitePermissions`, grant a site location access, and open its Site Permissions sheet. Location appears before Camera and Microphone with the correct allowed, blocked, and in-use icon states. Ask Each Time, Allow, and Never update the row and persisted choice as expected.
4. Open Settings › Site Permissions. The Location global picker offers Ask and Never only. A stored site's Location picker offers Ask Each Time, Always Allow, and Never Allow. Removing one site or all sites includes Location and supports Undo.
5. On a test page, retain the result of `navigator.permissions.query({ name: "geolocation" })` and listen with both `addEventListener("change", ...)` and `onchange`. Change Location in the on-site manager. The status changes once to the same state that the next request observes.
6. Start `watchPosition`, then select Never Allow or remove the site's permissions. The watch receives `PERMISSION_DENIED` and stops immediately. Changing a denied choice to Allow takes effect on reload or the next request; it does not restart an existing watch.
7. Open the same site in two tabs and request a permission in each. Resolve or close one tab. The other tab's request remains independent. A durable denial or removal still revokes matching active access in normal tabs.
8. Repeat the manager flow in a Fire tab. Choices affect only that tab's session, removal hides durable records only for that session, and no permission record is written or deleted.
9. With a page already loaded while the flag is on, turn `sitePermissions` off. The current page continues to use its existing shim. Reload or navigate: the new document has no shim interception and uses WebKit's behavior. Outstanding handler replies terminate safely.
10. Run `npm run validate-pixel-defs` from `iOS`. The validator checks `site_permissions.json5` for product target 7.234.0, then reaches the known baseline wide-event schema errors in data-clearing, data-import, and VPN-connection. Run `npx prettier ./PixelDefinitions --check`; all definitions pass formatting.

### Impact

High. This change completes the privacy-sensitive permission path for camera, microphone, and location, including settings, live page state, revocation, and rollback behavior.

#### What could go wrong?

- A page status could disagree with its next request → the data-driven transition table covers every stored, session, OS, and policy state through the same coordinator precedence.
- A manager change could leave a location watch active → denial and removal terminate native work immediately and refresh the original page status.
- A Fire tab could write durable permission history → Fire management uses session overrides only, with explicit no-write tests for choices, removal, and Undo.
- Turning the feature off could leave a half-active shim → the current document keeps its handler until commit, while feature updates rebuild the script set for the next document.
- Two tabs could resolve each other's requests → each tab owns its provider and FIFO; separate-tab tests resolve and close them independently.
- Geolocation pixels could expose browsing data → events use only approved type, action, and result tokens and never include a domain, host, URL, or origin.

### Quality Considerations

- V1 continues to allow the top-level document and exact same-origin iframes. All cross-origin, insecure, sandboxed, opaque, synthetic, and main-header-blocked frames are denied before prompting or telemetry.
- Delegated cross-origin iframes remain unsupported in v1. Revisit only after breakage evidence or when a public OS-managed API can provide an optional enhancement.
- Live permission-status registrations are document-scoped and clear on navigation, process replacement, or tab closure. No arbitrary cap drops a page-held listener.
- The repository-wide pixel validator has three unrelated baseline wide-event schema errors. The site-permissions definition itself validates and has no Phase 6 diff.
- The remaining project work is copy review, a final design-fidelity pass, translation finalization, rollout, and monitoring.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
