# Suggested PR title

`Add on-site permission management surfaces`

# Suggested PR body

Task/Issue URL: https://app.asana.com/1/137249556945/task/1217863452475661
Tech Design URL: https://app.asana.com/1/137249556945/task/1213800892997347
CC:

### Description

Adds camera and microphone permission management to the browser menus and Settings. It includes the on-site permission sheet, global and per-site controls, removal with conflict-safe Undo, immediate revocation across matching tabs, and the approved management pixels.

The feature remains behind `sitePermissions`, which is off by default. With the flag off, the Settings and browser-menu entries are absent, the sheet is unreachable, and existing media-capture behavior remains unchanged. Location management remains out of scope for this PR.

### Testing Steps

1. Run `xcodebuildmcp simulator build --project-path iOS/DuckDuckGo-iOS.xcodeproj --scheme "iOS Browser" --simulator-name "iPhone 17 Pro"` from the repository root. The production app builds successfully on iOS 26.4 with the normal project deployment target.
2. Run the focused Phase 4 suites for `SitePermissionsTests`, `BrowsingMenuBuilderTests`, `SettingsSitePermissionsViewModelTests`, and `SitePermissionsPixelHandlerTests`. The verified run passes 148 tests with no failures: 106 package tests and 42 selected unit tests.
3. Run `xcodebuildmcp simulator test --project-path iOS/DuckDuckGo-iOS.xcodeproj --scheme "iOS Browser" --simulator-name "iPhone 17 Pro" --extra-args=IPHONEOS_DEPLOYMENT_TARGET=16.0 --extra-args=-only-testing:SitePermissionsTests --extra-args=-only-testing:UnitTests`. The verified full run passes 6,726 tests with no failures and 37 baseline skips.
4. Run `./node_modules/.bin/validate-ddg-pixel-defs iOS/PixelDefinitions --file site_permissions.json5` and `./node_modules/.bin/prettier iOS/PixelDefinitions/pixels/definitions/site_permissions.json5 --check` from the repository root. The definition validates for target 7.234.0 and passes the formatting check.
5. Enable `sitePermissions`, make a persistent or session camera or microphone choice for a site, and open both browser-menu layouts. Site Permissions appears above Add Bookmark and opens the management sheet. It remains absent with no eligible state or when the flag is off.
6. Change a permission to Never Allow or remove the site's permissions while capture is active in multiple tabs for the same site. The store changes first, capture stops immediately in every matching normal tab, and Undo restores only records that have not been replaced by newer choices.
7. Open Settings › Site Permissions. Verify the two-option global pickers, locale-sorted Manage Sites list, three-option per-site pickers, System Settings link, and per-site and all-sites removal flows.

### Impact

High. This change lets users inspect and change privacy-sensitive camera and microphone decisions and immediately stops active capture after denial or removal.

#### What could go wrong?

- A shared menu change could regress the flag-off layout → the preferred detent now derives from the tagged Open Bookmarks entry and is tested with the permission row present and absent, both menu layouts, optional entries, and the YouTube Ad Block section.
- A denial or removal could leave capture running elsewhere → normal-mode revocation propagates to every matching live tab after the store mutation and revokes both managed types on removal.
- Fire browsing could write durable permission data → management choices remain session-local in Fire tabs, while external persistent changes clear conflicting Fire-session overrides.
- A globally denied request could expose a management row without a site record → globally blocked no-record requests are excluded from requested-this-visit state.
- Undo could overwrite a newer choice or restore session state → restoration uses the existing conflict-safe persistent snapshot and never restores ephemeral grants.
- Telemetry could expose the current site → management pixels contain no domain, host, URL, origin, or record count.

### Quality Considerations

- The sheet reuses `CardItem`, `CardItemList`, `SheetMetrics`, and the established UIKit sheet and iPad popover presentation patterns.
- Sheet rows use stored, active, and requested-this-visit state, while menu visibility requires a stored record or active session state. An explicit Ask record remains eligible; a request alone does not expose the menu entry.
- Settings lists only persistent records. Explicit Ask remains listed until removal, and ephemeral grants never appear.
- Global controls represent only Ask Each Time and Never Allow. Global Always Allow remains impossible.
- Grants take effect on reload or the next request. Explicit denial and removal revoke active camera or microphone capture immediately.
- Management event names match the approved cross-platform shapes. `from` remains a parameter, and all events are domain-free.
- Location rows and location management remain deferred to later phases.
- The multi-permission reminder and VoiceOver state strings still require copy review.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
