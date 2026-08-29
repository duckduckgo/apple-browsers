# Suggested PR title

`Add on-site permissions foundations`

# Suggested PR body

Task/Issue URL: https://app.asana.com/1/137249556945/task/1217863452475658
Tech Design URL: https://app.asana.com/1/137249556945/task/1213800892997347
CC:

### Description

Adds the storage and data-clearing foundations for on-site camera, microphone, and location permissions. It also adds the required permission icons and site-key normalization.

The feature is behind `sitePermissions` and is off by default. The permission data-clearing hook deliberately runs when the flag is off so a rollback cannot leave stored permission data behind. This PR adds no UI and does not change the existing web permission flows.

### Testing Steps

1. Run `xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"` from the repository root. The app builds successfully with the project deployment target.
2. With the current Xcode SDK, run `xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args=-only-testing:SitePermissionsTests --extra-args=-only-testing:UnitTests/FireExecutorTests --extra-args=IPHONEOS_DEPLOYMENT_TARGET=16.0`. The selected suites run 77 tests with no failures or skips.
3. Run `npm run check-wide-events` from `iOS/`. The wide-event consistency and schema checks pass.

### Impact

High. This change stores privacy-sensitive permission choices and participates in Fire data clearing.

#### What could go wrong?

- Two URLs could map to the wrong site record. The normalization tests cover schemes, ports, `www.`, subdomains, internationalized domains, and nonweb URLs.
- Fire could remove protected records or global defaults. The integration tests cover fireproofed sites, subdomains, implicit DuckDuckGo exemptions, tab scope, fire mode, and global-default preservation.
- Disabling the feature could strand stored data. The Fire integration is intentionally ungated and has a flag-off test.
- Undo could overwrite a newer choice. Snapshot tests verify that restoration skips sites with newer records.

### Quality considerations

- The store writes only explicit durable choices and explicit manager resets. Prompts and Allow Once grants do not create records.
- Per-site records and global defaults use separate property-list keys so data clearing can preserve global defaults.
- A global Always Allow state is not representable.
- The supplied 24×24 website-permissions SVG is included byte-for-byte with its design-resource accessor.
- Stored values are not encrypted, consistent with existing fireproofing and text-zoom preferences. Privacy review should account for this choice.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
