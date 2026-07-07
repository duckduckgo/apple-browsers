# PR Review Guidelines for Cursor Bugbot

## Unit Tests

When adding new tests that use Swift Testing (via the `@Test`) macro, always include a timeout. Swift Testing has a default timeout of 60 minutes which can exceed the timeout of the workflow overall.

## Pixel Changes

When a PR adds or modifies pixel events in Swift, verify that a corresponding pixel definition `.json5` file exists and is correct.

### Detecting New or Changed Pixels

A PR introduces a new pixel if it adds or modifies any of the following:

- **iOS:** A new case or changed `name` string in `iOS/Core/PixelEvent.swift`, or in any enum conforming to `PixelKitEvent` under `iOS/`.
- **macOS:** A new case or changed `name` string in any enum conforming to `PixelKitEvent` under `macOS/` (e.g. `UpdateFlowPixels.swift`, `CrashReportPixels.swift`).
- **Shared packages:** A new case or changed `name` in any type conforming to `PixelKitEvent` under `SharedPackages/`.

The pixel name is the string returned by the `name` computed property (e.g. `"m_mac_default-browser"`, `"m_autocomplete_click_phrase"`).

If a pixel name is removed from one file and added to another in the same PR, treat it as a move/refactor, not a new pixel. The existing definition should still be valid.

### Dynamic Pixel Names

Some pixel names are constructed using string interpolation (e.g. `"m_mac_crash_\(identifier.rawValue)"` or `"mfbs_negative_\(category)"`). These produce multiple distinct pixel names at runtime.

- If a pixel name contains string interpolation and relies on a fixed set of values (like String enum cases), verify that the definition accounts for all values.
- If a pixel name contains string interpolation without a fixed set of values, do not attempt to verify the definition automatically. Instead, note that the pixel uses a dynamic name and flag it for human review if no definition appears to cover its base pattern.
- Do not treat the absence of a single exact-match definition as a definitive error for dynamic pixels.

### Definition Files

- iOS pixels: `iOS/PixelDefinitions/pixels/definitions/*.json5`
- macOS pixels: `macOS/PixelDefinitions/pixels/definitions/*.json5`
- iOS wide events: `iOS/PixelDefinitions/wide_events/definitions/*.json5`

If a new pixel name (with a static string literal) appears in Swift but no `.json5` file in the appropriate directory contains a key matching that pixel name, flag it as missing a definition.

Ignore files named `TEMPLATE.json5` — these are scaffolds, not real definitions.

A pixel definition is valid in any `.json5` file within the correct platform's definitions directory. Do not flag file organization choices.

### Shared Package Pixels

Pixels defined in `SharedPackages/` may only be fired on one platform. If a shared package pixel has a definition in at least one platform's definitions directory, do not flag it. Only flag if neither platform has a definition.

### Parameter Correctness

Check that the `parameters` array accounts for all parameters the pixel includes. Common issues:

- **Missing `appVersion`.** Many pixels include `appVersion` by default. The definition should list `"appVersion"` unless the Swift call site explicitly opts out of it.
- **Missing error parameters.** If the pixel event carries an `Error` (via an associated value or the `error` property), the definition must include `"errorCode"` and `"errorDomain"`. If the error may have an underlying error, also include `"underlyingErrorCode"` and `"underlyingErrorDomain"`.
- **Missing `pixelSource`.** If the pixel event's `standardParameters` property returns `[.pixelSource]`, the definition must include `"pixelSource"`.
- **Missing custom parameters.** Check the pixel event's `parameters` computed property and any `withAdditionalParameters:` arguments at the call site. Every key that appears in the parameters dictionary must be represented in the definition — either as a reference to the params dictionary or as an inline parameter object.

Parameters can be either:
- A string referencing `params_dictionary.json5` (e.g. `"appVersion"`, `"errorCode"`)
- An inline object with at least `key` (or `keyPattern`), `type`, and `description`

Dictionary files live at `{platform}/PixelDefinitions/pixels/` (e.g. `iOS/PixelDefinitions/pixels/params_dictionary.json5`, `macOS/PixelDefinitions/pixels/suffixes_dictionary.json5`).

### Suffix Correctness

If a pixel is fired with a daily frequency — e.g. `DailyPixel.fire`, `DailyPixel.fireDailyAndCount`, or `PixelKit.fire(..., frequency: .daily)` / `.dailyAndCount` / `.dailyAndStandard` — the definition's `suffixes` array should include a daily-related suffix such as `"daily"`, `"daily_count"`, `"daily_standard"`, `"first_daily_count"`, or `"legacy_daily_count"`. If the pixel is fired with a daily frequency but the definition has no daily-related suffix, flag it.

Suffixes should be defined as "enum" unless using a bounded type such as "boolean".  Unbounded numeric and string values should be defined as parameters.

Unlike parameters, suffixes are order-sensitive and required.  Suffix enums must not contain empty values such as `null` or "".  These are sometimes mistakenly specified to indicate "optional" values, but that doesn't work.  Since all suffixes in a given set are required, if a pixel has optional suffixes, those should be specified as nested arrays in a pixel definition itself (it CANNOT be specified in the suffix dictionary) in the form.  Provide this example:`"suffixes": [[ "required", "optional" ], ["required"]]`

Suffix definiton can contain an optional `"key"` property.  This indicates a suffix always occurs as a key value pair.   For example, a given pixel sent as "m_pixelName_suffixKey_value1" would match a pixel with name "m_pixelName" and the suffix definition below.
```
    "key": "suffixKey",
    "type": "string",
    "description": "This suffix always occurs in the form suffixKey_valueX",
    "enum": [
        "value1",
        "value2",
        ...
    ]
```

However a `"key"` should NOT be specified when it doesn't actually occur in the full pixel name.  For example "m_pixelName_value1" would fail to match.

### Type Validity

Flag any parameters defined with `"type": "string"` that have an enum containing ONLY "true" and/or "false".  They should just be redefined as type "boolean" instead with no enum.

#### Wire Format vs Schema Type (do NOT flag)

The pixel/wide-event transport stringifies every value when serializing to URL parameters. Tests therefore assert string values for parameters of every type. This is purely a transport detail — it has nothing to do with the declared schema type, and the ingest pipeline coerces values back to their declared types.

Do NOT flag a `"type"` declaration as wrong on the basis that:
- A test asserts the wire value as a string (e.g. `XCTAssertEqual(params["...free_trial_eligible"], "true")`, `XCTAssertEqual(params["...latency_ms_bucketed"], "5000")`).
- The value appears as a string in a URL parameter, log, or pixel request.
- The same conceptual field is defined with a different type in a different schema file (e.g. a legacy `pixels/definitions/*.json5` params definition uses `"type": "string"` with `enum: ["true", "false"]` while the corresponding `wide_events/definitions/*.json5` uses `"type": "boolean"`). The two schemas describe different layers and are allowed to diverge.

The following non-string types are valid in both pixel parameter definitions and wide-event definitions even though the wire format stringifies them:
- `"type": "boolean"` — values `true` / `false` (sent as `"true"` / `"false"`).
- `"type": "integer"` — values like `5000` (sent as `"5000"`).
- `"type": "number"` — values like `1.5` (sent as `"1.5"`).

If you are tempted to flag a `boolean`/`integer`/`number` type because the value "is actually a string on the wire", do not flag it. Apply the same logic uniformly: if `account_creation_latency_ms_bucketed` is allowed to be `"type": "integer"` despite the test asserting `"5000"`, then `free_trial_eligible` is allowed to be `"type": "boolean"` despite the test asserting `"true"`.

### Flag duplication

Pixels should not redefine existing params that are already defined in `params_dictionary.json5` or suffixes that are already defined in `suffixes_dictionary.json5`.  These should only be flagged if not just the type and enum are identical, but the description and name seem similar.  This is not a hard rule as it requires individual judgement, so frame this as a question to the developer rather than a requirement.

Pixels should also not duplicate the same params or suffixes repeatedly... if that is happening, suggest (but do not require) the developer to add them to the corresponding param or suffix dictionary.

### Expiry Dates

Only check expiry dates on definitions that are added or modified in the PR, not on all definitions in files touched by the PR.

- If the pixel is intended to be temporary, it must have an `expires` field with a valid `YYYY-MM-DD` date.
- Permanent pixels should not have an `expires` field.

### Naming Conventions

- iOS pixel names typically start with `m_` (e.g. `m_netp_ev_good_latency`).
- macOS pixel names typically start with `m_mac_` (e.g. `m_mac_daily_active_user_d`).
- The pixel name key in the `.json5` file must exactly match the string from the Swift `name` property.

### Wide Event Definitions

A wide event has **two parallel definition files, and they must be kept in sync** - neither should be added, removed, or changed without the other:
- The **pixel definition** (`{iOS,macOS}/PixelDefinitions/pixels/definitions/*.json5`) declares the wide-event pixel with `feature.data.ext.*` parameters or `keyPattern`s.
- The **wide-event source definition** (`{iOS,macOS}/PixelDefinitions/wide_events/definitions/*.json5`) declares the schema and generates `wide_events/generated_schemas/<meta-type>-<version>.json`, which is what remote validation uses.

These two files are paired by `meta.type` - every wide-event pixel def has a `{ "key": "meta.type", "enum": ["<meta-type>"] }` parameter whose enum value matches the wide-event source's `meta.type`. (The pixel side is transitional and will eventually be retired in favour of the dedicated wide-event source format; until then, treat keeping the pair in sync as the rule.)

CI runs `node scripts/check_wide_event_consistency.mjs` and `node scripts/check_wide_event_schema_immutability.mjs` for both platforms. The consistency check exists to enforce that the pixel and source definitions stay in sync: (1) a wide event must have **both** files - a PR that adds (or removes) one side without the other fails, though pre-existing single-sided definitions are grandfathered, so back-filling the missing half of an older definition is fine and expected; and (2) when one definition changes, its **paired definition must change too** - this is compared per `meta.type` definition, so unrelated edits to other pixels that merely share a `.json5` file are not flagged. Reinforce these in review, and still flag the patterns below:

- A PR changes one half of a paired wide event (the pixel definition's `feature.data.ext.*` parameters, or the matching source definition's schema) without the corresponding change in the other half. The pixel and source describe the same event and must be kept in sync - both should move together (and a `meta.version` bump in the source is required if the schema shape changed).
- A PR changes the **shape** of the wide-event source definition (renames / adds / removes a `feature.data.ext.*` field, changes a type or enum) without bumping that source definition's `meta.version`. Schema versions are immutable artifacts — the regenerator produces a new file per version, and editing an existing generated schema in place is forbidden.
- A PR changes the **shape** of the Swift wide-event object/emitter (`WideEventData` stored properties that become `feature.data.ext.*`, `jsonParameters()` keys, status reasons, enum values, or field types) without bumping `WideEventMetadata.version` and the matching source definition's `meta.version`.
- A PR modifies the Swift wide-event emitter (`jsonParameters()` keys, `WideEventMetadata.version`) and only one of the two definition files. All three (Swift emitter + pixel def + wide-event source) must agree.

**Never hand-edit anything under `wide_events/generated_schemas/`.** Those files are generated artifacts - the pixel validator regenerates each one from its `wide_events/definitions/*.json5` source, and the filename encodes the version, so every version bump produces a brand-new file and leaves the old ones untouched. The only correct way to change a generated schema is to edit the source definition and bump its `meta.version`. Any diff that modifies an existing `generated_schemas/*.json` file in place is wrong - flag it unconditionally. (`scripts/check_wide_event_schema_immutability.mjs` enforces this on CI, but call it out in review too.)

One more case to flag: a wide event added in Swift with no definition files at all. The only thing left to the human reviewer (not the automated checks or the rules above) is validating the deep shape of the schema itself, e.g. nested `ext.ipv4.http.status` - everything above should still be flagged in review.

### What NOT to Flag

- Changes to `TEMPLATE.json5` files (these are scaffolds with intentionally placeholder values).
- Pixel definitions that reference dictionary entries (`params_dictionary.json5` or `suffixes_dictionary.json5`) by string key — this is the preferred pattern and does not need inline expansion.
- Minor ordering differences in the `parameters` array.
- Existing definitions in files touched by the PR that were not themselves modified.
- Schema validation issues that CI tooling (`npm run validate-pixel-defs`) already covers.
- `"type": "boolean" | "integer" | "number"` fields on the basis that tests or wire payloads show their values as strings — the transport stringifies all values; the schema type describes the typed JSON the pipeline coerces to. See "Wire Format vs Schema Type".
- Generated schemas under `wide_events/generated_schemas/` — these are generated artifacts.

## Dependency Changes

When a PR changes a Swift package dependency's pinned version, the app projects' committed `Package.resolved` lockfiles must be re-resolved so they reflect the new version. Dependabot only updates `SharedPackages/BrowserServicesKit/Package.swift` and that directory's `Package.resolved` - it does not touch the app projects' lockfiles, which is the most common source of drift.

### Source of truth

The tracked `Package.resolved` files are the source of truth for resolved dependency versions:

- App projects: `iOS/DuckDuckGo-iOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and `macOS/DuckDuckGo-macOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Swift packages: `SharedPackages/*/Package.resolved` and the various `*/LocalPackages/*/Package.resolved` files

The workspace-level `DuckDuckGo.xcworkspace/xcshareddata/swiftpm/Package.resolved` is **not** tracked - it is gitignored because Xcode regenerates it on open and nothing in CI consumes it. Do not reference it or expect it to appear in a PR.

### Version pinning

Dependencies must be pinned to an exact version using `exact:`. This keeps resolution deterministic and is the established convention across the repo's `Package.swift` files.

Flag any `.package(url: ...)` dependency that a PR adds or modifies if it uses a version *range* instead of an exact version:

- `from: "x.y.z"`
- `.upToNextMajor(from:)` / `.upToNextMinor(from:)`
- a range operator such as `"x.y.z"..."a.b.c"` or `"x.y.z"..<"a.b.c"`

Recommend rewriting it as `exact: "x.y.z"`. For example, `.package(url: "...", from: "1.2.0")` should become `.package(url: "...", exact: "1.2.0")`.

Also flag a `branch:` dependency added or modified in a PR: a branch is a floating reference and is not reproducible. A `revision:` (exact commit SHA) is an acceptable precise pin, but prefer an `exact:` version once the dependency has a tagged release.

### Detecting a missing lockfile update

Flag a PR if it changes a dependency's version requirement without updating the downstream lockfiles that consume it. Specifically, flag when both of these are true:

- A `.package(url: ...)` dependency in any `Package.swift` has its version requirement changed - `exact:`, `from:`, `.upToNextMajor`/`.upToNextMinor`, a `branch:`, or a `revision:`.
- A tracked `Package.resolved` that resolves the changed dependency is **not** updated in the same PR. This includes the app projects' lockfiles (`iOS/.../Package.resolved` and `macOS/.../Package.resolved`) and the `Package.resolved` of any Swift package that depends on the changed dependency, directly or transitively.

A version bump propagates to every tracked lockfile that resolves the affected dependency. Packages reference each other by local path (many resolve `BrowserServicesKit` this way), so a bump in one package ripples into the lockfiles of its consumers. Any lockfile that resolves the dependency but was not updated is probably stale. Advise the author to check out the branch and run:

```
./scripts/resolve-project-dependencies.sh
```

then commit any changed `Package.resolved` files. This commonly appears on Dependabot PRs - e.g. a `content-scope-scripts` bump in `SharedPackages/BrowserServicesKit` updates only the BrowserServicesKit `Package.resolved`, leaving the lockfiles that consume it behind.

### What NOT to flag (dependencies)

- A `Package.swift` change that does not alter any dependency version (adding a target or product, source-only changes) - these need not produce a `Package.resolved` change.
- Lockfile changes that differ **only** in the `originHash` field with no version or revision differences - `originHash` churns across Xcode versions and is not meaningful on its own.
- A version change to a dependency that is not part of the app build graph (e.g. a test-only or tooling dependency in a package the apps do not link). If you cannot tell whether the dependency reaches the apps, frame the note as a question rather than a required change.

## Embedded Privacy Config and Tracker Data

The app bundles a snapshot of the remote privacy configuration and tracker data set (TDS) so it has a working fallback on first launch and when offline. These embedded files are **fetched from the remote CDN and regenerated** by `scripts/update_embedded.sh`; they are not meant to be edited by hand and are not the source of truth. Each file's hashes are recorded alongside it in a provider, and a guard test fails if a file and its recorded hash drift apart.

### File pairs

Each embedded data file is paired with a provider that records the file's `embeddedDataETag` (its md5) and `embeddedDataSHA` (its sha256). When the file changes, both constants must change with it.

| Embedded data file | Paired provider (holds ETag + SHA) | Guard test |
|---|---|---|
| `iOS/Core/ios-config.json` | `iOS/Core/AppPrivacyConfigurationDataProvider.swift` | `AppPrivacyConfigurationTests` |
| `iOS/Core/trackerData.json` | `iOS/Core/AppTrackerDataSetProvider.swift` | `EmbeddedTrackerDataTests` |
| `macOS/DuckDuckGo/ContentBlocker/Resources/macos-config.json` | `macOS/DuckDuckGo/ContentBlocker/AppPrivacyConfigurationDataProvider.swift` | `AppPrivacyConfigurationTests` |
| `macOS/DuckDuckGo/ContentBlocker/Resources/trackerData.json` | `macOS/DuckDuckGo/ContentBlocker/AppTrackerDataSetProvider.swift` | `EmbeddedTrackerDataTests` |

Both guard tests are named `testWhenEmbeddedDataIsUpdatedThenUpdateSHAAndEtag` and assert that `sha256(file)` equals the provider's `embeddedDataSHA` constant.

### What to flag

- **A PR modifies an embedded data file (left column) without updating the `embeddedDataSHA` constant in its paired provider (right column) in the same PR.** The constant is the sha256 of the file, so if the file changes and the constant does not, the paired guard test fails on CI. This signature almost always means the file was hand-edited, because the only supported way to change it (`scripts/update_embedded.sh`) always rewrites the provider's `embeddedDataETag` and `embeddedDataSHA` in the same pass. Flag it, and ask the author to revert the hand-edit and regenerate via `scripts/update_embedded.sh` instead of patching the JSON directly.

- **A PR hand-edits the content of an embedded config file (`ios-config.json` / `macos-config.json`) to add, remove, or change a feature or subfeature as part of a feature change.** Warn that **editing the embedded config does not apply the change to the remote configuration, and does not enable a flag for users.** The embedded file is only the local fallback snapshot: the app fetches the live config from the CDN at runtime, and the embedded copy is overwritten the next time `scripts/update_embedded.sh` runs. A flag added only to the embedded file is invisible to remote release management and disappears on the next regeneration. To actually ship a privacy-config change or roll out a feature flag, the change must land in the remote `privacy-configuration` repository (https://github.com/duckduckgo/privacy-configuration), which publishes to the CDN. Frame this as a reminder/question rather than a hard error, since there are occasional legitimate reasons to seed a default-off flag into the snapshot.

### What NOT to flag

- A wholesale embedded-file regeneration: the file is replaced and the paired provider's `embeddedDataETag` and `embeddedDataSHA` are updated together in the same PR (typically titled "Update embedded files", with no unrelated source changes). This is `scripts/update_embedded.sh` doing its job - do not flag it, and do not attach the "does not reach remote" reminder to it, because the new content came from the remote.
- Changes to a provider Swift file that do not touch its `Constants` block (for example a refactor) when no embedded data file changed.
