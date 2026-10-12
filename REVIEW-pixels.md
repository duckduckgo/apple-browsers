# Pixel and wide-event review rules

Read this when a PR adds or modifies a pixel event, a wide event, or any file
under `iOS/PixelDefinitions/` or `macOS/PixelDefinitions/`. It extends
`REVIEW.md`, which holds the severity calibration and the global skip list.

A missing or wrong definition breaks the remote data pipeline silently — nothing
fails to build and nothing crashes — so treat these as 🔴 Important unless a rule
below says otherwise.

## Detecting a new or changed pixel

A PR introduces a pixel if it adds or changes a case, or a `name` string, in:

- **iOS:** `iOS/Core/PixelEvent.swift`, or any enum conforming to
  `PixelKit.Event` under `iOS/`
- **macOS:** any enum conforming to `PixelKit.Event` under `macOS/`, such as
  `UpdateFlowPixels.swift` or `FireButtonPixel.swift`
- **Shared packages:** any type conforming to `PixelKit.Event` under
  `SharedPackages/`

The pixel name is the string returned by the `name` computed property, e.g.
`fire_started_macos` or `m_autocomplete_click_phrase`, plus any prefix PixelKit
prepends. The key in the `.json5` must match that name exactly. Older names
start `m_` (iOS) or `m_mac_` (macOS); new ones drop the prefix, and new macOS
names end in `_macos` instead.

If a name is removed from one file and added to another in the same PR, treat it
as a move, not a new pixel — the existing definition still stands.

## A definition must exist

- iOS pixels: `iOS/PixelDefinitions/pixels/definitions/*.json5`
- macOS pixels: `macOS/PixelDefinitions/pixels/definitions/*.json5`
- iOS wide events: `iOS/PixelDefinitions/wide_events/definitions/*.json5`
- macOS wide events: `macOS/PixelDefinitions/wide_events/definitions/*.json5`

A static pixel name in Swift with no matching key in the right platform's
directory is missing its definition. Any `.json5` within that directory counts —
do not flag file organisation choices.

A `SharedPackages/` pixel may fire on only one platform, so flag it only if
*neither* platform has a definition.

**Dynamic names.** An interpolated name such as
`"m_mac_crash_\(identifier.rawValue)"` or `"mfbs_negative_\(category)"` produces
several distinct runtime names.

- If the interpolation draws on a fixed set of values, like String enum cases,
  check the definition accounts for all of them
- If it does not, do not try to verify automatically. Note that the name is
  dynamic and flag it for a human if no definition appears to cover its base
  pattern
- The absence of a single exact match is not proof of an error for a dynamic
  pixel

## Parameters

Every key the pixel actually sends must be represented in `parameters`. Check
the event's `parameters` computed property and the call site, where extras
arrive either as `withAdditionalParameters:` (legacy) or in the options
argument, as `options: .parameters([...])` or
`PixelKit.Options(additionalParameters: [...])`.

Common gaps:

- **`appVersion`** — included by default on many pixels. The definition should
  list it unless the call site explicitly opts out
- **Error parameters** — an event carrying an `Error`, via an associated value or
  its `error` property, needs `errorCode` and `errorDomain`, plus
  `underlyingErrorCode` and `underlyingErrorDomain` if there may be an
  underlying error
- **`pixelSource`** — required when the event's `standardParameters` returns
  `[.pixelSource]`

A parameter is either a string referencing `params_dictionary.json5` (e.g.
`appVersion`, `errorCode`) or an inline object with at least `key` (or
`keyPattern`), `type`, and `description`. Dictionaries live at
`{iOS,macOS}/PixelDefinitions/pixels/`.

Do not flag minor ordering differences in the `parameters` array, or a
dictionary reference that has not been inlined — the reference is the preferred
pattern.

## Suffixes

Unlike parameters, suffixes are **order-sensitive and all required**.

- A pixel fired with a daily frequency — `.daily`, `.dailyAndCount` or
  `.dailyAndStandard` — needs a daily-related suffix:
  `daily`, `daily_count`, `daily_standard`, `first_daily_count`, or
  `legacy_daily_count`. Flag a daily-fired pixel whose definition has none
- Suffixes should be defined as `enum` unless the type is genuinely bounded,
  like `boolean`. Unbounded numeric and string values belong in parameters
- A suffix enum must not contain empty values such as `null` or `""`. These get
  added to signal "optional" and do not work, because every suffix in a set is
  required. Optional suffixes are expressed as nested arrays in the pixel
  definition itself — this **cannot** go in the suffix dictionary:
  `"suffixes": [["required", "optional"], ["required"]]`
- An optional `"key"` property means the suffix always occurs as a key/value
  pair, so `m_pixelName_suffixKey_value1` matches a definition with
  `"key": "suffixKey"`. Do **not** specify `key` when it does not actually
  appear in the full name — `m_pixelName_value1` would then fail to match

## Triggers

`triggers` records what causes the pixel to fire. Choose it with this
procedure; the full definitions and worked examples are in the
[trigger classification guide](https://github.com/duckduckgo/pixel-schema/blob/main/docs/trigger-classification.md).

```
Classify by the EVENT THAT CAUSES THE PIXEL TO FIRE — never by dedupe cadence
("daily"/"unique" suffixes) or the delivery mechanism.

1. Deliberate user action (tap, click, toggle, menu selection, swipe, gesture,
   prompt/query submission)?  → user_interaction
   • A surface shown 1:1 because of a gesture (menu on tap, dialog behind a
     button, screen entered from an explicit flow) is user_interaction.
   • user_submitted ONLY for consent-scoped submission of the user's own data
     (breakage report, feedback). The opener button is user_interaction.
2. Surface displayed WITHOUT the user asking? → impression
   • Litmus: display code has an eligibility gate (feature flag, subscription
     state, view-count threshold, cooldown) → impression. Only gate is "user
     navigated here" → user_interaction.
3. Injected scripts detected page content (captcha, adwall, CMP, ads)?
   → web_detection
4. Automatic feature operation runs / completes / changes state (migration,
   sync cycle, job engine, token refresh, update detection, state observer)?
   → feature_lifecycle
   • Async completion of a user-initiated flow that can outlive the UI or be
     driven by a non-user party (billing observer, remote sync peer, retrying
     backend call) → feature_lifecycle. Synchronous completion inside the
     user's action → user_interaction.
5. A timer or scheduled/delayed job literally fires it (rollup, sampler,
   watchdog, absence-of-event check)? → scheduled
   • If the timer merely DETECTS something, classify by what was detected:
     anomaly → exception; a user toggle noticed by a poll → user_interaction.
6. Error/crash → exception. Launch or foreground → startup. Page loaded →
   page_load. New tab → new_tab. DDG search → search_ddg.
7. One pixel name covering several events (e.g. an event=shown|clicked param)?
   → list every applicable trigger; triggers is an array.

Store-and-forward: when counters are recorded at event time and transmitted
later by a worker, classify by the RECORDED event, never the flusher.

Use "other" only when nothing above fits, and say why in the description.
```

Worked examples from this repo:

- `m_mac_privacy-pro_toolbar_button_shown`: the upsell state machine decides to
  show the button, so `impression`. Its `*_popover_shown` siblings are shown on
  the user's click, so `user_interaction`
- `webTelemetry_captcha_*`: immediate EventHub pixels for an injected-script
  detection, so `web_detection`. The `*_day` and `*_week` rollups of the same
  signals are fired by the period timer, so `scheduled`
- `m_ios_dbp_optout_stage_*`: PIR job-engine stage events, so
  `feature_lifecycle`
- `m_mac_settings_auto-clear_on`: a daily snapshot sent from
  `applicationDidBecomeActive`, so `startup`
- `m_ios_onboarding_*`: one name carries `shown` and `clicked` in a parameter,
  so `["impression", "user_interaction"]`

Check triggers only on definitions the PR added or modified. Flag `["other"]`
when the description does not say why nothing else fits, and flag a trigger
that contradicts the firing code. A wrong trigger does not break the pipeline,
so these are 🟡 Nit.

## Types

Flag any parameter defined as `"type": "string"` whose enum contains only
`"true"` and/or `"false"`. It should be `"type": "boolean"` with no enum.

**Do not flag a type on the grounds that the value looks like a string on the
wire.** The pixel and wide-event transport stringifies every value when
serialising to URL parameters, so tests assert string values for parameters of
every type. That is purely a transport detail; the declared type describes the
typed JSON the ingest pipeline coerces back to. `boolean`, `integer`, and
`number` are all valid, and none of the following is a reason to flag one:

- A test asserting the wire value as a string, e.g.
  `XCTAssertEqual(params["...free_trial_eligible"], "true")` or
  `XCTAssertEqual(params["...latency_ms_bucketed"], "5000")`
- The value appearing as a string in a URL parameter, log, or pixel request
- The same concept typed differently in a different schema file — a legacy
  `pixels/definitions/*.json5` using `"type": "string"` with
  `enum: ["true", "false"]` while the paired `wide_events/definitions/*.json5`
  uses `"type": "boolean"`. The two describe different layers and may diverge

Apply this uniformly: if `account_creation_latency_ms_bucketed` may be
`"type": "integer"` despite a test asserting `"5000"`, then
`free_trial_eligible` may be `"type": "boolean"` despite a test asserting
`"true"`.

## Duplication

A pixel should not redefine a param already in `params_dictionary.json5`, or a
suffix already in `suffixes_dictionary.json5`. Flag only when the description
and name look similar too, not merely when the type and enum match — this needs
individual judgement, so frame it as a question to the developer rather than a
requirement.

If the same params or suffixes repeat across many pixels, suggest — but do not
require — moving them into the corresponding dictionary.

## Expiry dates

Check expiry only on definitions the PR added or modified, not on everything in
a file it touched.

- A pixel intended to be temporary needs an `expires` field with a valid
  `YYYY-MM-DD` date
- A permanent pixel should have no `expires` field

## Wide events

A wide event has **two parallel definition files whose event payload formats
must be kept in sync**, paired by `meta.type`:

- The **pixel definition**
  (`{iOS,macOS}/PixelDefinitions/pixels/definitions/*.json5`) declares the
  wide-event pixel with `feature.data.ext.*` parameters or `keyPattern`s, and
  carries a `{ "key": "meta.type", "enum": ["<meta-type>"] }` parameter
- The **wide-event source**
  (`{iOS,macOS}/PixelDefinitions/wide_events/definitions/*.json5`) declares the
  schema and generates
  `wide_events/generated_schemas/<meta-type>-<version>.json`, which remote
  validation uses

The pixel side is transitional and will eventually be retired in favour of the
dedicated wide-event format; until then, keeping the pair in sync is the rule.
Pre-existing single-sided definitions and field-level inconsistencies are
grandfathered, but a PR may not introduce a new one.

Flag:

- A payload-format change on one side — a `feature.data.ext.*` field, type,
  enum, or constraint — with no compatible representation on the other. An
  unchanged pixel `keyPattern` may already cover a new source field, in which
  case no redundant pixel edit is required, but a source whose schema shape
  changed still needs a `meta.version` bump
- A **shape** change to the wide-event source (a `feature.data.ext.*` field
  renamed, added, or removed; a type or enum changed) without bumping that
  source's `meta.version`. Schema versions are immutable artifacts
- A **shape** change to the Swift emitter — `WideEventData` stored properties
  that become `feature.data.ext.*`, `jsonParameters()` keys, status reasons,
  enum values, field types — without bumping `WideEventMetadata.version` **and**
  the matching source's `meta.version`. All three must agree
- A PR that modifies the Swift emitter and only one of the two definition files
- A `keyPattern` added or edited without anchoring on both `^` and `$`, e.g.
  `"feature\\.data\\.ext\\.(...)_status"` instead of
  `"^feature\\.data\\.ext\\.(...)_status$"`. Patterns match as unanchored
  substrings, so a missing trailing `$` lets a pattern over-match longer sibling
  keys sharing its prefix: a `_status` pattern also matches a `_status_reason`
  key and validates it against the wrong enum, rejecting valid values. Flag any
  unanchored `keyPattern` unless a partial match is clearly intended
- Any in-place edit of an existing `wide_events/generated_schemas/*.json`. These
  are generated artifacts; the filename encodes the version, so every bump
  produces a brand-new file and leaves the old ones untouched. The only correct
  way to change one is to edit the source definition and bump its
  `meta.version`. **Flag unconditionally**
- A wide event added in Swift with no definition files at all

What is genuinely left to the human reviewer is validating the deep shape of the
schema itself, e.g. nested `ext.ipv4.http.status`. Everything above should still
be flagged in review.

## PixelKit injection

`PixelKitFiring.fire`'s `event` parameter is the `PixelKit.Event` *protocol*, not
a concrete enum, so leading-dot shorthand does not resolve against it:
`pixelFiring?.fire(.someCase)` fails to compile and must be spelled
`pixelFiring?.fire(Pixel.Event.someCase)`, or whatever the concrete event type
is. This is a compiler error, not a style nit, and only a real type-checking
build catches it — `swiftc -parse` does not — so flag it as broken rather than
assuming CI already screens it out.

New production code should inject `PixelFiring?`, defaulting to
`PixelKit.shared`, rather than call the static `PixelKit.fire`, which the
PixelKit README reserves for existing code. Its tests should mock with
`PixelKitMock` (`@_spi(Testing) import PixelKit`). Flag a new type that fires
through the static entry points — that is new debt in the direction the
codebase is migrating away from.
