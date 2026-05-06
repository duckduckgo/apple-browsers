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

Wide events in `iOS/PixelDefinitions/wide_events/definitions/*.json5` and `macOS/PixelDefinitions/wide_events/definitions/*.json5` use a different schema from regular pixels. They have `meta`, `feature`, and `feature.data` sections instead of `suffixes` and `parameters`. Validating wide event schema correctness is out of scope for automated review — leave wide event definitions to human reviewers. Only flag if a wide event is added in Swift but has no definition file at all.

In particular, do NOT:
- Flag field `type` declarations (`boolean`, `integer`, `number`, `string`) on the basis of test wire-format assertions or URL-encoded transport behavior — see "Wire Format vs Schema Type" above.
- Flag a wide-event field for "diverging" from the type used in a legacy `pixels/definitions/*.json5` entry with the same key. The two schemas are independent; iOS and macOS wide-event definitions are also independent and may legitimately differ.
- Flag generated schemas under `wide_events/generated_schemas/` — these are generated artifacts.

### Validating changes to package.resolved files

If there are changes in `iOS/DuckDuckGo-iOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` or `macOS/DuckDuckGo-macOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` then only flag these if there are actual differences in the versions compared to the content of `DuckDuckGo.xcworkspace/xcshareddata/swiftpm/Package.resolved` which is our source of truth.

### What NOT to Flag

- Changes to `TEMPLATE.json5` files (these are scaffolds with intentionally placeholder values).
- Pixel definitions that reference dictionary entries (`params_dictionary.json5` or `suffixes_dictionary.json5`) by string key — this is the preferred pattern and does not need inline expansion.
- Minor ordering differences in the `parameters` array.
- Existing definitions in files touched by the PR that were not themselves modified.
- Schema validation issues that CI tooling (`npm run validate-pixel-defs`) already covers.
- `"type": "boolean" | "integer" | "number"` fields on the basis that tests or wire payloads show their values as strings — the transport stringifies all values; the schema type describes the typed JSON the pipeline coerces to. See "Wire Format vs Schema Type".
- Generated schemas under `wide_events/generated_schemas/` — these are generated artifacts.

