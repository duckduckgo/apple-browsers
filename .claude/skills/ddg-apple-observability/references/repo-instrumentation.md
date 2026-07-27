# Instrumentation in this repo

Two primitives. Both can power an SLO. They differ in what they can capture, and the
difference decides which one a journey needs.

## Pixels

`PixelKit`. Declared as `Pixel.Event` cases in `iOS/Core/PixelEvent.swift` (macOS has its
own `PixelKitEvent` conformances), defined in `{iOS,macOS}/PixelDefinitions/pixels/definitions/*.json5`.
88 definitions on iOS today.

A stateless HTTP GET: a name plus flat parameters, fired and forgotten. Three cadences,
and they measure different things:

| Call | Semantics | Good for |
|---|---|---|
| `Pixel.fire` | every occurrence | volume of an interaction |
| `DailyPixel.fireDailyAndCount` | once per day per user, plus a raw count | **users affected**, which a raw count cannot give you |
| `UniquePixel.fire` | once per install, ever | lifecycle milestones: activation, first use |

Two pixels give two independent counts, so a ratio between them is a ratio of populations
rather than of attempts. Nothing links a given attempt's fire to its outcome's fire. That
is fine when both fire from the same code path microseconds apart, and it is fine when the
denominator is a natural population rather than an attempt (sessions, installs).

## Wide events

`WideEvent` in `SharedPackages/BrowserServicesKit/Sources/PixelKit/WideEvent`, defined in
`{iOS,macOS}/PixelDefinitions/wide_events/definitions/*.json5`. 9 definitions today.

One row per attempt, assembled over the life of a flow via `startFlow` / `updateFlow` /
`completeFlow(status:)` / `discardFlow`, correlated by a global ID. What that buys:

- **Survives termination.** Flows persist through `WideEventStoring`, so an attempt
  outlives app or extension death and can be resolved on a later launch via
  `completionDecision(for: .appLaunch)`. `vpn-connection` does this, reporting
  `status_reason` of `partial_data`, `timeout`, or `retried`.
- **Four terminal outcomes.** `WideEventStatus` is `.success(reason:)`, `.failure`,
  `.cancelled`, `.unknown(reason:)`. User abandonment is separable from real failure
  without inventing a convention.
- **Latency on the same row as the outcome.** `MeasuredInterval` lands as `latency_ms` and
  per-step variants, so "succeeded within Xs" is computable per attempt.
- **Bounded dimensions**, enum-typed and schema-validated.

Constraints that can invalidate a proposed SLI:

- **Sampled at flow start** by `WideEventSampler`. Ratios survive sampling; absolute counts
  do not. Never define an SLI that needs a true count from a wide event, and on macOS
  check that the sampled volume can support the percentile you are asking for.
- **Schemas are immutable once shipped.** Any content change needs a version bump, enforced
  by `scripts/check_wide_event_schema_immutability.mjs`. The fields have to be right first
  time, so enumerate the drilldown categories in the proposal.
- **Expensive.** A schema, an immutability contract, a version, a definitions PR, a
  sampling decision. Nine exist across the whole repo against 88 pixels. Proposing six new
  ones for one feature is not a real recommendation.

## Choosing

Follow the shape of the journey, not whether it carries an SLO.

**Pixel** when the outcome is known at a single point in time: a tap, an impression, an
immediate error, a milestone, an error-impact count.

**Wide event** when any of these hold:

- The journey has multiple stages that can each fail.
- It crosses an async boundary, a process, or an app launch.
- You need latency and outcome tied to the same attempt.
- You need cancellation distinguished from failure.

The deciding test when it is close: **can the user's app die between the attempt and the
outcome?** If yes and it happens often, two pixel counts drift apart independently and the
ratio quietly lies. A wide event resolves the orphan instead.

## Finding what already exists

```
# pixels for a feature
grep -rn "<feature>" iOS/Core/PixelEvent.swift
ls {iOS,macOS}/PixelDefinitions/pixels/definitions/ | grep -i <feature>

# wide events
ls {iOS,macOS}/PixelDefinitions/wide_events/definitions/
grep -rln "WideEventData" iOS/DuckDuckGo macOS/DuckDuckGo SharedPackages

# firing sites
grep -rn "Pixel.fire\|fireDailyAndCount\|UniquePixel.fire\|startFlow\|completeFlow" <feature dir>
```

Wide-event instrumentation tends to live in a `WideEvent/` subdirectory next to the feature
(`iOS/DuckDuckGo/AIChat/WideEvent`, `SharedPackages/VPN/Sources/VPN/WideEvent`) or under
`SharedPackages/BrowserServicesKit/Sources/Subscription/WideEvents`.

Read the `.json5` definition of anything you plan to reuse. It states the terminal statuses,
the enum values, and the latency fields that actually exist, which is what determines
whether an SLI is computable today.

## Not this skill's job

Field naming, API calls, schema mechanics, validation commands, code. Once the SLIs are
agreed, implementation goes to the wide-event guidance or `.cursor/rules/pixels.mdc`.
