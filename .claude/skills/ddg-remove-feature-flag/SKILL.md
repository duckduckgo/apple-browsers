---
name: ddg-remove-feature-flag
description: Use when removing a feature flag from iOS or macOS, keeping either its enabled or its disabled code path.
---

# Remove a feature flag

Removing a flag turns one of its two code paths into the only one. Know which before you start:

- **Approved** (rolled out, "Keep Feature"): keep the path taken when the flag is on.
- **Rejected** (abandoned, "Remove Feature"): keep the path taken when the flag is off. This usually
  deletes the feature's code entirely.

- **Experiment** (has a cohort enum): "approved" doesn't say which cohort won. Keep the winning
  cohort's path, and ask if you weren't told which one it is. The experiment must already have
  ended in the remote configuration: enrolled users keep sending its metrics until it does.

If you weren't told which, ask. Don't infer it from the flag's default value.

1. **Find every use** on the target platform. Search for the flag's case name ignoring case
   (`git grep -i`): it can appear as `.flag`, `FeatureFlag.flag.rawValue`, in test stubs, launch
   arguments and doc comments. The other platform can have its own flag with the same name; leave it
   alone.
2. **Remove the flag case** from `FeatureFlag.swift` in
   `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/` or
   `macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/`: the case, its `///` comment, its
   `Config(...)` entry and any other `switch` over it. Note the subfeature in its
   `.remoteReleasable(<Subfeature>.case)` source. An experiment's nested cohort enum goes too.
3. **Remove the subfeature case**, but only if no other flag or code uses it (search for it first).
   Find its enum from the type in `.remoteReleasable(...)`, on either platform:
   `iOSBrowserConfigSubfeature.swift` next to the iOS `FeatureFlag.swift`, or `MacOSBrowserConfigSubfeature`
   or a shared parent such as `DataImportSubfeature` or `PrivacyProSubfeature` in
   `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift`.
   If that was the enum's last case, delete the enum too: Swift rejects a raw-value enum with no
   cases. Keep its `PrivacyFeature` case unless nothing else uses it.
4. **Resolve every call site** to the kept path. Replace `featureFlagger.isFeatureOn(.flag)` with the
   constant, and an experiment's `resolveCohort`/`assignedCohort` with the winning cohort, then simplify: collapse the `if`, inline the kept branch and delete code only the other
   path reached, such as views, view model properties, `UserText` strings and assets. Remove a
   `FeatureFlagger` parameter or property only when this flag was its last use.
5. **Pixels:** if the deleted path fired pixels or experiment metrics, remove their definitions with
   the `ddg-add-pixel` skill, but only those no remaining code fires (search for each first: both
   paths often fire the same pixel).
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

Done when the flag no longer appears in the target platform's code and tests (the embedded
configuration JSON and the other platform's own flags don't count), every touched platform builds, and
the tests cover only the kept behaviour.
