# PixelKit

PixelKit sends **pixels**: one-off telemetry events delivered as an HTTP GET to
`improving.duckduckgo.com`, carrying a name and a handful of parameters. It is the system both the
macOS browser and (increasingly) the iOS browser use.

PixelKit deliberately knows nothing about any specific pixel. Events are declared by the app or
shared package that owns them, and PixelKit only assembles the name, applies the sending rules, and
performs the request. That keeps it lean and reusable across apps.

**Contents**

1. [Quick start](#quick-start)
2. [Declaring a pixel](#declaring-a-pixel)
3. [Firing a pixel](#firing-a-pixel)
4. [Choosing a frequency](#choosing-a-frequency)
5. [How the name is built](#how-the-name-is-built)
6. [Naming exceptions](#naming-exceptions)
7. [What actually gets sent](#what-actually-gets-sent)
8. [Options](#options)
9. [De-duplication and throttling keys](#de-duplication-and-throttling-keys)
10. [Setting PixelKit up in an app](#setting-pixelkit-up-in-an-app)
11. [Checking your pixel locally](#checking-your-pixel-locally)
12. [Testing code that fires pixels](#testing-code-that-fires-pixels)
13. [Related documents](#related-documents)

## Quick start

Declare an event, then fire it:

```swift
enum OnboardingPixel: PixelKit.Event {
    case completed(step: String)

    var name: String {
        switch self {
        case .completed: return "m_onboarding_completed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .completed(let step): return ["step": step]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }
}

// `pixelFiring` is an injected `PixelFiring` — see Firing a pixel.
pixelFiring?.fire(OnboardingPixel.completed(step: "3"), frequency: .dailyAndCount)
```

On an iPhone that sends two requests:

```
/t/m_onboarding_completed_daily_ios_phone?appVersion=7.244.0&pixelSource=phone&step=3
/t/m_onboarding_completed_count_ios_phone?appVersion=7.244.0&pixelSource=phone&step=3
```

You do not write any naming code to get that shape. See
[How the name is built](#how-the-name-is-built).

## Declaring a pixel

A pixel is a type conforming to `PixelKit.Event`. Group related pixels as cases of one enum.

```swift
public protocol Event {
    var name: String { get }                                   // required
    var parameters: [String: String]? { get }                  // required
    var standardParameters: [PixelKitStandardParameter]? { get } // required
    var error: NSError? { get }                                // defaulted
    var namePrefix: PixelKitNamePrefix { get }                 // defaulted: .platformDefault
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { get } // defaulted: .standard
}
```

Only the first three normally need writing. The defaults on the other three are what a new pixel
wants.

**`name`** is the pixel name before any prefix or suffix. Make it self-documenting; do not copy the
legacy shorthand style (`ml`, `mp`, `mf`).

**`parameters`** are the pixel's own query parameters. Bucket numeric values rather than sending
them verbatim, and never include PII, URLs, or anything user-identifiable.

**`standardParameters`** opts into parameters PixelKit can supply. Today the only case is
`.pixelSource`, which sends the platform the pixel came from.

**`error`** has a reflection-based default that finds an `NSError` in an enum case's associated
values, so `case somethingFailed(Error)` needs no extra code. Declare it explicitly if your error is
not an associated value.

### Two more things a pixel needs

A pixel is not finished when the Swift compiles:

1. **A definition** in `iOS/PixelDefinitions/pixels/definitions/*.json5` or the macOS equivalent,
   listing its owners, triggers, suffixes and parameters. CI validates these.
2. **Privacy triage**, before adding anything that could correlate users — notably
   `Options.withATB` and `Options.withRetry`.

## Firing a pixel

**Inject a `PixelFiring` instance.** That is the expected approach for all new code: it makes the
dependency explicit and lets tests substitute `PixelKitMock` instead of reaching for global state.

```swift
final class MyFeature {
    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func doSomething() {
        pixelFiring?.fire(MyPixel.somethingHappened, frequency: .daily)
    }
}
```

`PixelFiring?` defaulted to `PixelKit.shared` is the established pattern in this codebase: callers
get the real instance without wiring anything, tests pass a mock, and the optional keeps the type
honest about `shared` being `nil` before `setUp` runs.

### `fire` or `fireAsync`

```swift
// Fire and forget. Correct for almost every pixel.
pixelFiring?.fire(MyPixel.somethingHappened)
pixelFiring?.fire(MyPixel.somethingHappened, frequency: .daily)

// Only when the caller genuinely needs the outcome.
let result = try await pixelFiring?.fireAsync(MyPixel.somethingHappened)
// FireResult? — .sent, or .suppressed when the frequency rules held it back
```

Telemetry should not make a caller wait, so prefer `fire`. `fireAsync` throws only if the request
itself failed; suppression by a frequency rule is reported as `.suppressed`, not an error.

### The static entry points

`PixelKit.fire(...)` and `PixelKit.fireAsync(...)` forward to the `PixelKit.shared` singleton:

```swift
PixelKit.fire(MyPixel.somethingHappened, frequency: .daily)   // legacy
```

`PixelKit.fire` silently no-ops when `setUp` has not run; the static `PixelKit.fireAsync` throws
`PixelKitError.notConfigured` instead, since a caller that awaited a result cannot honestly be told
the pixel was either sent or suppressed.

These exist for backward compatibility with code written before pixel firing was injected, and a lot
of the codebase still calls them. **Do not use them in new code** — a type that fires pixels through
the singleton cannot be tested without mutating global state, and it hides the dependency from
whoever constructs it. Prefer injection, and migrate call sites to it when you are already changing
the surrounding code.

## Choosing a frequency

`Frequency` controls both how often a pixel is allowed to send and what suffix it gets.

| Case | Behaviour | Suffix(es) |
|---|---|---|
| `.standard` | Every time | none |
| `.daily` | Once per day | `_daily` |
| `.monthly` | Once per calendar month (UTC) | `_monthly` |
| `.dailyAndCount` | Once per day, plus every time | `_daily` + `_count` |
| `.dailyAndStandard` | Once per day, plus every time | `_daily` + none |
| `.uniqueByName` | Once per install; name must end `_u` | none |
| `.uniqueByNameAndParameters` | Once per install per parameter set | none |
| `.sample(percentage:)` | A random N% of calls | `_sample<n>` |
| `.debounce(seconds:)` | At most once per window | none |
| `.legacyDaily` | Once per day | `_d` |
| `.legacyDailyAndCount` | Once per day, plus every time | `_d` + `_c` |
| `.legacyInitial` | Once per install, no `_u` requirement | none |
| `.legacyDailyNoSuffix` | Once per day | none |

`.dailyAndCount` is the usual choice for anything that can spike: the `_daily` leg counts affected
users, the `_count` leg counts occurrences. The `legacy` cases exist for pixels that already ship
those suffixes; prefer the modern equivalents for new pixels.

Monthly pixels are not comparable with ATB-derived MAU stats.

## How the name is built

The name is assembled in four steps. Only `Frequency`, passed at the call site, comes from outside
the event — the rest is declared on the event, so every call site firing it produces the same name.

```
m_example_count_ios_phone
│ │      │     │
│ │      │     └── 4. platform marker   Event.platformSuffixPolicy
│ │      └──────── 3. frequency suffix  the Frequency passed to fire
│ └─────────────── 2. name              Event.name
└───────────────── 1. prefix            Event.namePrefix
```

| Step | Source | Default |
|---|---|---|
| 1. Prefix | `Event.namePrefix` | `.platformDefault` |
| 2. Name | `Event.name` | required |
| 3. Frequency suffix | the `Frequency` passed to `fire` | `.standard`, which adds nothing |
| 4. Platform marker | `Event.platformSuffixPolicy` | `.standard`; iOS only, empty on macOS |

### Step 1 — prefix

`PixelKitNamePrefix`:

| Case | macOS | iOS |
|---|---|---|
| `.platformDefault` | `m_mac_` prepended, unless the name already starts with it; a `DebugEvent` gets `m_mac_debug_` | nothing prepended |
| `.none` | nothing | nothing |
| `.custom("m_")` | `m_` | `m_` |

Use `.none` when `name` is already the complete pixel name. On iOS `.platformDefault` and `.none`
produce the same result, because iOS names carry too varied a set of prefixes to correct centrally.

### Step 3 — frequency suffix

See the [frequency table](#choosing-a-frequency). A frequency that fires twice sends two pixels, one
per suffix.

### Step 4 — platform marker

`PixelKitPlatformSuffixPolicy`. The marker is `_ios_phone` or `_ios_tablet`, chosen by the `source`
given to `setUp`. On macOS it is empty, so all three cases produce the same name there.

Below, an event named `m_example` fired with `.dailyAndCount` — the `_count` leg shown:

| Case | macOS | iOS (iPhone) | iOS (iPad) |
|---|---|---|---|
| `.standard` | `m_example_count` | `m_example_count_ios_phone` | `m_example_count_ios_tablet` |
| `.legacyBeforeFrequencySuffix` | `m_example_count` | `m_example_ios_phone_count` | `m_example_ios_tablet_count` |
| `.legacyOmitted` | `m_example_count` | `m_example_count` | `m_example_count` |

`.standard` matches the `["first_daily_count", "platform", "form_factor"]` suffix order the pixel
definitions declare, and matches what the legacy iOS `Pixel` produces. The two legacy cases exist
only to hold the names of pixels that shipped before the marker was applied consistently. **Do not
use them for new pixels.**

### Worked examples

| Event | `namePrefix` | `platformSuffixPolicy` | `Frequency` | Sent on iOS |
|---|---|---|---|---|
| `name: "example"` | `.custom("m_")` | `.standard` | `.dailyAndCount` | `m_example_daily_ios_phone`, `m_example_count_ios_phone` |
| `name: "m_example"` | `.none` | `.standard` | `.daily` | `m_example_daily_ios_phone` |
| `name: "m_example"` | `.none` | `.legacyOmitted` | `.daily` | `m_example_daily` |
| `name: "example"` | `.platformDefault` | `.standard` | `.standard` | `example_ios_phone` (on macOS: `m_mac_example`) |

These tables are asserted by `PixelNameBuildingExamplesTests`, and iOS parity with the legacy
`Pixel` by `PixelKitLegacyNamingParityTests` in the iOS test target.

## Naming exceptions

Four cases sidestep parts of the pipeline. All are pre-existing and none apply to new pixels.

**Experiment pixels.** A name starting with `experiment` skips steps 1, 3 and 4 entirely and gets
its own marker from `addExperimentPlatformSuffix`. `platformSuffixPolicy` is ignored.

**Self-marking names.** `OSDistributionPixel` builds the platform and form factor into `name`, so it
declares `.none` and `.legacyOmitted` to stop PixelKit adding a second set.

**Host-chosen prefixes.** A shared package whose prefix depends on the app it was built into cannot
declare it statically. Wrap the event instead:

```swift
pixelKit.fire(event.prefixed(platform.pixelNamePrefix), frequency: .dailyAndCount)
```

`prefixed(_:)` returns the event with an explicit prefix, forwarding everything else.
`DataBrokerProtectionSharedPixelsHandler` and `OnboardingPixelReporter` both use it.

**Per-case naming.** An event whose cases need different prefixes switches on `self`, as
`GeneralPixel` and `AttributedMetricPixel` do.

## What actually gets sent

One GET request per pixel leg, to `https://improving.duckduckgo.com/t/<name>`, with the parameters
below as the query string. The host is overridable with the `PIXEL_BASE_URL` environment variable.

### Parameters

| Parameter | Sent when |
|---|---|
| `appVersion` | Always, unless `Options.withoutAppVersion` |
| `test=1` | `DEBUG` builds only |
| `pixelSource` | The event lists `.pixelSource` in `standardParameters` |
| `channel` | `setUp` was given a `channel` |
| `atb` | `Options.withATB`, and a `PixelKitParameterProviding` was injected at `setUp` |
| `e`, `d` | The event carries an error: code and domain |
| `ue`, `ud`, `ue2`, `ud2`, … | Underlying errors, one numbered pair per nesting level |
| `sqlrc`, `sqlerc` | SQLite result codes, when present in the error's `userInfo` |
| `originalPixelTimestamp`, `retriedPixel` | The pixel was replayed from the retry queue |
| the event's own | `Event.parameters` |
| extras | `Options.additionalParameters`, which win on key collision |

Error descriptions are deliberately never sent — they can leak personal information.

### Headers

`setUp`'s `defaultHeaders`, plus `X-DuckDuckGo-MoreInfo` and `X-DuckDuckGo-Client`
(`iOS` / `iPadOS` / `macOS`). The app's `fireRequest` closure adds the user agent.

### A full example

Firing `OnboardingPixel.completed(step: "3")` with `.dailyAndCount` on an iPhone, in a release
build, sends:

```
GET https://improving.duckduckgo.com/t/m_onboarding_completed_daily_ios_phone
        ?appVersion=7.244.0&pixelSource=phone&step=3
GET https://improving.duckduckgo.com/t/m_onboarding_completed_count_ios_phone
        ?appVersion=7.244.0&pixelSource=phone&step=3

X-DuckDuckGo-Client: iOS
X-DuckDuckGo-MoreInfo: See https://help.duckduckgo.com/duckduckgo-help-pages/privacy/atb/
```

The next call the same day sends only the `_count` leg.

## Options

`PixelKit.Options` carries transport and payload. **Nothing in it affects the pixel's name.**

| Preset | Effect |
|---|---|
| `.default` | App version included, nothing else |
| `.withoutAppVersion` | Drops `appVersion`, e.g. crash reports |
| `.withRetry` | Persists a failed send and replays it later |
| `.withATB` | Adds the user's ATB cohort |
| `.parameters([...])` | Extra query parameters |

`Options` is a value type, so mutate a preset for combinations:

```swift
var options = PixelKit.Options.withATB
options.additionalParameters = ["source": "menu"]
```

`.withRetry` and `.withATB` both change what reaches the server and need privacy triage first.

## De-duplication and throttling keys

Daily, monthly, unique and debounce frequencies remember when a pixel last fired. The key is the
name from **steps 1 and 2 only** — the frequency suffix and the `.standard` platform marker are
excluded. A `.daily` pixel therefore fires once per device, not once per form factor.

Changing an event's `namePrefix` or `platformSuffixPolicy` changes this key, so a daily pixel may
fire one extra time on the build that changes it.

## Setting PixelKit up in an app

Each app process configures a shared instance once, at startup:

```swift
PixelKit.setUp(dryRun: isDebugOrInternalBuild,
               appVersion: AppVersion.shared.versionNumber,
               source: source.rawValue,        // decides the iOS platform marker
               session: "ios-browser",
               defaultHeaders: [:],
               defaults: appGroupDefaults,
               parameterProvider: IOSPixelKitParameterProvider()) { name, headers, params, _, _, onComplete in
    // perform the request
}
```

On iOS, pick `.iPadOS` only for `UIUserInterfaceIdiom.pad`; every other idiom is `.iOS`. That
matches the legacy `Pixel`, so both systems agree on the marker.

`dryRun` logs pixels instead of sending them. It still applies the frequency rules, but compresses
the daily and monthly windows to **two minutes**, so you can re-trigger a daily pixel while testing
without waiting for the next day.

## Checking your pixel locally

In a debug build, every fired pixel is written to `pixelkit-validation-log.txt` in the app's Caches
directory. Trigger your pixel in the simulator, then validate the log against the definitions:

```bash
./iOS/scripts/validate_pixels.sh
```

Fired pixels are also logged live, so you can watch them in Console:

```
👾[Daily and Count-Fired] m_onboarding_completed_daily_ios_phone ["step": "3", ...]
```

## Testing code that fires pixels

Inject `PixelKitMock` and inspect what it recorded. The testing types are behind an SPI group, so
import accordingly:

```swift
@_spi(Testing) import PixelKit

let pixelKit = PixelKitMock()
MyFeature(pixelFiring: pixelKit).doSomething()

XCTAssertEqual(pixelKit.actualFireCalls.first?.pixel.name, "m_something_happened")
```

Where `SharedTestUtilities` is linked (the macOS targets), you can declare the calls up front and
assert them in one go instead:

```swift
let pixelKit = PixelKitMock(expecting: [
    ExpectedFireCall(pixel: MyPixel.somethingHappened, frequency: .daily)
])
MyFeature(pixelFiring: pixelKit).doSomething()
pixelKit.verifyExpectations(file: #filePath, line: #line)
```

`ExpectedFireCall` compares the event's name, parameters, error and `namePrefix`, plus the
frequency, any additional parameters and `includeAppVersionParameter` — not the final wire name. To assert the wire name, construct a real `PixelKit` with a `fireRequest`
closure that captures it, as the naming tests in this package do.

See [TestingSupport/README.md](TestingSupport/README.md) for why these types live where they do.

## Related documents

| Document | Covers |
|---|---|
| [RetryQueue/README.md](RetryQueue/README.md) | How failed pixels are persisted and replayed |
| [TestingSupport/README.md](TestingSupport/README.md) | `PixelKitMock` and friends |
| `.cursor/rules/pixels.mdc` | Repo-wide pixel conventions, definitions, validation |
| [WideEvent](../../../WideEvent/README.md) | Separate package for multi-step flows reported as a single record |
