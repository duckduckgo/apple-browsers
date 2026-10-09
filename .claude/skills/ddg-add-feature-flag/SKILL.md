---
name: ddg-add-feature-flag
description: Use when adding, removing or changing a feature flag or an A/B/N experiment on iOS or macOS.
---

# Add or change a feature flag

Flags live in `FeatureFlag.swift` in `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/` and
`macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/`. Copy the shape of the neighbouring
cases; the steps below cover what the neighbours don't show.

1. **Get the flag's Asana task URL** from the user. The flag case carries it as a `///` doc comment,
   and so does its subfeature.
2. **Add the subfeature** the remote config controls:
   - iOS only: `iOSBrowserConfigSubfeature.swift`, next to `FeatureFlag.swift`.
   - macOS only: `MacOSBrowserConfigSubfeature` in
     `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift`.
   - A feature with its own parent, such as `AIChatSubfeature`: that parent's enum in the same
     `PrivacyFeature.swift`.
3. **Add the flag case** and its `Config(...)` entry in the `config` switch. `source` is
   `.remoteReleasable(<Subfeature>.case)`, or `.disabled` to switch the flag off everywhere.
   - `defaultValue` applies only while the remote config doesn't list the subfeature. Once the
     config lists it, the config decides for everyone, internal users included. `.internalOnly` is
     the usual starting point.
   - Keep `supportsLocalOverriding` at its default `true` unless the flag must not be toggled from
     the debug menu. macOS UI tests crash at launch when they set a flag that doesn't allow it.
   - macOS: pass `category:` (`FeatureFlagCategory.swift`) to group the flag in the debug menu.
4. **Gate the code** with `featureFlagger.isFeatureOn(.flag)` on an injected `FeatureFlagger`; on
   iOS, default the parameter to `AppDependencyProvider.shared.featureFlagger`. When the flag picks
   between two UI implementations that bind at launch, read it once at startup instead, as
   `FireModeCapability.resolve(using:)` does in `MainCoordinator`, so a mid-session toggle can't
   leave the UI half-switched.
5. **Experiment (A/B/N):**
   - Nest a `<Name>Cohort: String, FeatureFlagCohortDescribing` enum in `FeatureFlag` and pass it as
     `cohortType:`.
   - `featureFlagger.resolveCohort(for: .flag)` enrolls the device, so call it only where the user
     meets the difference. Anywhere else, read with `assignedCohort(for:)`, which never enrolls.
   - Fire metrics with `PixelKit.fireExperimentPixel` (PixelExperimentKit), and declare them under
     the experiment in `{iOS,macOS}/PixelDefinitions/pixels/native_experiments.json5`.
6. **Test** both states with the platform's mock: on iOS,
   `MockFeatureFlagger(enabledFeatureFlags: [.flag])` from `iOS/SharedTestUtils`; on macOS and in
   SharedPackages, the PrivacyConfig `MockFeatureFlagger` with `featuresStub[flag.rawValue]` set.
7. **Tell the user** that the rollout happens in the `duckduckgo/privacy-configuration` repository,
   under the subfeature name from step 2. The embedded config files in this repository are generated
   copies, so editing them turns nothing on.

Done when the flag compiles on every platform it targets, both of its states are tested, and the user
has the subfeature name to add to privacy-configuration.
