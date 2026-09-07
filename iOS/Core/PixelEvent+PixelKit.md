# `Pixel.Event` on PixelKit

`PixelEvent+PixelKit.swift` fires `Pixel.Event` through PixelKit. This file is the reference for
why that is safe, and for how to migrate a legacy call site.

## Why this is safe

Legacy `Pixel` built a name as `<name><frequencySuffix>` and `URL.makePixelURL` then appended
`_ios_<formFactor>`. `namePrefix: .none` plus `platformSuffixPolicy: .standard` reproduces exactly
that, so migrated pixels keep the names they shipped with.

`Pixel.Event` itself is unchanged: it stays the catalogue of legacy pixel names. Only the way it
reaches the network moves.

## Migrating a call site

Frequency comes from the legacy call shape:

| Legacy call | PixelKit frequency |
|---|---|
| `Pixel.fire(pixel:)` | `.standard` |
| `Pixel.fire(pixel:debounce: n)` | `.debounce(seconds: n)` |
| `DailyPixel.fire(pixel:)` | `.legacyDailyNoSuffix` |
| `DailyPixel.fireDailyAndCount(pixel:)`, `"_daily"` / `"_count"` | `.dailyAndCount` |
| …`(pixelNameSuffixes: .legacyDailyPixelSuffixes)`, `"_d"` / `"_c"` | `.legacyDailyAndCount` |
| …`(pixelNameSuffixes: .dailyAndStandardSuffixes)`, `"_daily"` / `""` | `.dailyAndStandard` |
| `UniquePixel.fire(pixel:)`, name ends `"_u"` | `.uniqueByName` |
| `UniquePixel.fire(pixel:)`, name ends `"_unique"` | `.legacyInitial` |
| `persistentPixel.fire(…)` | `.standard` + `.withRetry` |
| `persistentPixel.fireDailyAndCount(…)` | matching daily frequency + `.withRetry` |

`_unique` names must use `.legacyInitial`, not `.uniqueByName`. PixelKit's `.uniqueByName` guards
on a `_u` suffix and returns *without firing* when it is absent. A `_unique` pixel routed there
would silently stop being sent. Both frequencies throttle under the same storage key, so their
once-ever state is shared and migrated together.

Parameters and transport come from the legacy arguments:

| Legacy argument | PixelKit |
|---|---|
| `withAdditionalParameters: p` | `options: .parameters(p)` |
| `includedParameters: [.appVersion]` (the default) | `options: .default` |
| `includedParameters: []` | `options: .withoutAppVersion` |
| `includedParameters: [.appVersion, .atb]` | `options: .withATB` |
| `includedParameters: [.isInternalUser]` | dropped: no call site ever passed it |
| `error: e` | `event.withError(e)` |
| `withHeaders: h` | `Options.headers` |
| `allowedQueryReservedCharacters: c` | `Options.allowedQueryReservedCharacters` |
| `onComplete: { … }` | `fireAsync`, or dropped |
| `forDeviceType: nil` | `event.withoutPlatformSuffix` |

Two legacy statics have PixelKit equivalents rather than wrappers here: `UniquePixel.cohort(from:)`
becomes `PixelKit.cohort(from:)`, and `Pixel.Event.lastFireDate(uniquePixelStorage:)` becomes
`PixelKit.pixelLastFireDate(event:frequency:)`.
