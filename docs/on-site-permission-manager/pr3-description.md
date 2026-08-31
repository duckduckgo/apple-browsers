# Suggested PR title

`Add on-site camera and microphone permission flows`

# Suggested PR body

Task/Issue URL: https://app.asana.com/1/137249556945/task/1217863452475660
Tech Design URL: https://app.asana.com/1/137249556945/task/1213800892997347
CC:

### Description

Connects ordinary website camera and microphone requests to DuckDuckGo's on-site permission flow. It adds the site prompt, native permission ordering, denied-permission recovery, in-use tracking, the redesigned Voice Search reminder, and the approved Phase 3 pixels.

The feature remains behind `sitePermissions`, which is off by default. With the flag off, both existing media-capture paths and the legacy Voice Search alert remain unchanged. Duck.ai keeps its existing behavior in both flag states.

### Testing Steps

1. Run `xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"` from the repository root. The app builds with the normal project deployment target.
2. Run `xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args=-only-testing:SitePermissionsTests --extra-args=-only-testing:UnitTests/TabViewControllerMediaCapturePermissionRoutingTests --extra-args=-only-testing:UnitTests/SitePermissionsPixelHandlerTests --extra-args=IPHONEOS_DEPLOYMENT_TARGET=16.0`. The final focused run passes 104 tests with no failures or skips.
3. Run `xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args=-only-testing:SitePermissionsTests --extra-args=-only-testing:UnitTests --extra-args=IPHONEOS_DEPLOYMENT_TARGET=16.0`. The verified full run passes 6,668 tests with no failures and 37 baseline skips.
4. Run `./node_modules/.bin/validate-ddg-pixel-defs iOS/PixelDefinitions --file site_permissions.json5` and `./node_modules/.bin/prettier iOS/PixelDefinitions/pixels/definitions/site_permissions.json5 --check` from the repository root. The new definition validates and passes the formatting check.
5. Enable `sitePermissions`, visit an HTTPS page that requests camera, microphone, or both, and choose each site-level option. The custom prompt appears before any native prompt, all three actions resolve the complete request, and denied site choices never trigger iOS permission UI.
6. Allow the site, then deny a fresh iOS permission request. WebKit is denied and one no-action toast identifies the freshly denied permission or permissions.
7. Request a permission that is already blocked in iOS Settings. WebKit is denied before one reminder appears; Change Permissions opens the DuckDuckGo page in System Settings, and Cancel dismisses the reminder.
8. Deny microphone access, then start Voice Search with the flag on and off. The redesigned three-action reminder appears only with the flag on; Hide Voice Search disables the existing feature setting. The legacy alert remains unchanged with the flag off.

### Impact

High. This change controls privacy-sensitive website access to the camera and microphone.

#### What could go wrong?

- A native prompt could appear before DuckDuckGo explains the request → atomic preflight and ordering tests cover single and combined requests.
- A combined request could spend one native prompt even though the other permission is already blocked → mixed-state tests verify that neither prompt is requested.
- Two permission surfaces could overlap → each tab keeps recovery in the same FIFO until the surface dismisses.
- A stale request could grant access after navigation or process replacement → request context and observation generations invalidate late callbacks.
- Allow Once could survive after capture ends → independent camera and microphone observation tests expire only the matching grant.
- The feature could change existing behavior while disabled → frozen browser and Duck.ai matrices remain unchanged, and the legacy Voice Search alert has focused coverage.

### Quality Considerations

- Site-level Allow commits when the user chooses it and is never rewritten by an iOS denial.
- Combined recovery uses one surface. Recovery copy names only the permission types that are actually blocked.
- Pixels use approved, domain-free names. Native prompt results are emitted once per individual prompt, and Case A toasts intentionally emit no pixel.
- The supplied screenshots define the card geometry, material, spacing, button treatment, Dynamic Type scrolling, and VoiceOver behavior.
- Copy review is still required for the combined camera-and-microphone dialog and recovery strings.
- The existing camera usage description, `Allows you to upload photographs and videos`, also appears for live website capture. It ships unchanged because revising it would affect the existing upload flow, but it should be included in copy review.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
