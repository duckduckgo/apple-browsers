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
