---
name: ddg-remove-feature-flag
description: Use when removing a feature flag from iOS or macOS, keeping either its enabled or its disabled code path.
---

# Remove a feature flag

Removing a flag turns one of its two code paths into the only one. Know which before you start:

- **Approved** (rolled out, "Keep Feature"): keep the path taken when the flag is on.
- **Rejected** (abandoned, "Remove Feature"): keep the path taken when the flag is off. This usually
  deletes the feature's code entirely.

If you weren't told which, ask. Don't infer it from the flag's default value.

1. **Find every use.** Search for the flag's case name ignoring case (`git grep -i`): it can appear
   as `.flag`, `FeatureFlag.flag.rawValue`, in test stubs, launch arguments and doc comments.
2. **Remove the flag case** from `FeatureFlag.swift` in
   `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/` or
   `macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/`: the case, its `///` comment, its
   `Config(...)` entry and any other `switch` over it. Note the subfeature in its
   `.remoteReleasable(<Subfeature>.case)` source. An experiment's nested cohort enum goes too.
3. **Remove the subfeature case**, but only if no other flag or code uses it (search for it first):
   - iOS: `iOSBrowserConfigSubfeature.swift`, next to `FeatureFlag.swift`.
   - macOS: `MacOSBrowserConfigSubfeature`, or a parent such as `DataImportSubfeature`, in
     `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift`.
   Remove only the case. Leave the parent enum and its feature in place, even if they end up empty.
4. **Resolve every call site** to the kept path. Replace `featureFlagger.isFeatureOn(.flag)` with the
   constant, then simplify: collapse the `if`, inline the kept branch and delete code only the other
   path reached, such as views, view model properties, `UserText` strings and assets. Remove a
   `FeatureFlagger` parameter or property only when this flag was its last use.
5. **Pixels:** if the deleted path fired pixels or experiment metrics, remove their definitions with
   the `ddg-add-pixel` skill.
6. **Update the tests.** Delete the flag's stubs (`featuresStub[...]` on macOS,
   `enabledFeatureFlags` on iOS). Delete tests that only cover the removed path. A test that compared
   both states becomes a test of the kept behaviour. Don't weaken assertions about the kept path.
7. **Leave the remote configuration alone.** The embedded privacy configuration JSON files are
   generated copies, and the subfeature is removed from `duckduckgo/privacy-configuration`
   separately, once no supported app version reads it.
8. **Verify:** build every platform the change touches (both when `SharedPackages` changed), run the
   tests you changed and the tests of the code you simplified, and lint the changed files.

Title the PR `iOS: Remove <flag> feature flag` or `macOS: Remove <flag> feature flag`, and describe it
in one line: the flag was approved (or rejected) and its conditional code is removed.

Done when the flag name no longer appears in the repository, every touched platform builds, and the
tests cover only the kept behaviour.
