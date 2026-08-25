# PixelKit

This package is meant to provide basic support for firing pixel across different targets.

This package was designed to not really know specific pixels.  Those can be defined
individually by each target importing this package, or through more specialized
shared packages. 

This design decision is meant to make PixelKit lean and to make it possible to use it
for future apps we may decide to make, without it having to carry over all of the business
domain logic for any single app.

## Retry on failure

A pixel that fails to send is dropped, unless it opts into the retry queue:

```swift
pixelKit.fire(MyPixel.somethingImportant, options: .withRetry)
```

Opting in persists a failed send and replays it later, with two extra parameters
(`originalPixelTimestamp` and `retriedPixel`) that the pixel must be privacy triaged for first. It is
off by default for exactly that reason. See [RetryQueue/README.md](RetryQueue/README.md).

## Naming lives on the event

A pixel's name is a contract with its definition in `PixelDefinitions` and with whatever queries it,
so both halves of it are declared on the event, not passed at the call site:

| Property | Controls | Default |
|---|---|---|
| `namePrefix` | what goes in front of `name` | `.platformDefault` |
| `platformSuffixPolicy` | where the iOS platform marker goes | `.standard` |

`PixelKit.Options` carries transport and payload only — headers, extra parameters, retry, ATB. It
has nothing that can change a pixel's name. That is deliberate: when naming was per-call, two call
sites firing the same event could disagree about what it was called and nothing caught it, which is
how both the platform-suffix drift and `GeneralPixel.jsPixel`'s duplicated prefix conditional
happened.

`PixelKitNamePrefix` has three cases:

| Case | Result on macOS | Result on iOS |
|---|---|---|
| `.platformDefault` | `m_mac_` prepended unless the name already starts with it (`m_mac_debug_` for a `DebugEvent`) | nothing prepended |
| `.none` | nothing prepended | nothing prepended |
| `.custom("m_")` | `m_` prepended | `m_` prepended |

`.none` is what the old `doNotEnforcePrefix: true` argument meant. It was being repeated at every
call site of the events that needed it, so it moved onto those events.

### When the prefix depends on the host, not the pixel

`DataBrokerProtectionSharedPixelsHandler` and `OnboardingPixelReporter` each take a `Platform` at
construction and turn it into `m_mac_` or `m_ios_`. That is a per-process fact the shared event type
cannot know, but it is still naming, so it does not go back into `Options`. Use the decorator:

```swift
pixelKit.fire(event.prefixed(platform.pixelNamePrefix), frequency: .dailyAndCount)
```

`prefixed(_:)` returns the same event wearing an explicit prefix, forwarding everything else.

## Platform and form-factor suffixes

On iOS every pixel name ends in a marker saying which platform and form factor it came from,
`_ios_phone` or `_ios_tablet`. On macOS the marker is empty and none of this applies.

The marker is appended when the request is built, after any frequency suffix, so a `.dailyAndCount`
pixel called `m_example` sends `m_example_daily_ios_phone` and `m_example_count_ios_phone`. That
order matches what the pixel definitions declare (`suffixes: ["first_daily_count", "platform",
"form_factor"]`) and what iOS' legacy `Pixel` type has always produced.

**New pixels need to do nothing.** `PixelKit.Event.platformSuffixPolicy` defaults to `.standard`,
which is the behaviour above.

`PixelKitPlatformSuffixPolicy` has two other cases, and they exist only to freeze names that shipped
before the marker was applied consistently:

| Case | Result | Why it exists |
|------|--------|---------------|
| `.standard` | `m_example_count_ios_phone` | The default. Use this. |
| `.legacyBeforeFrequencySuffix` | `m_example_ios_phone_count` | What conformance to `PixelKitEventWithCustomPrefix` used to imply on its own. |
| `.legacyOmitted` | `m_example_count` | What every other event used to produce on iOS, which is why some pixels cannot be told apart from their macOS counterparts by name. |

Do not add a legacy case to a new pixel. Adding one to an existing pixel is a rename: coordinate
with the pixel's owners and update its `suffixes` in `PixelDefinitions` to match.

Note that the marker is deliberately kept out of the throttling key, so a `.daily` pixel fires once
per device rather than once per form factor.
