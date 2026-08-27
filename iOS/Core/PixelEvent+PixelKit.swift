//
//  PixelEvent+PixelKit.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import PixelKit

// Fires `Pixel.Event` through PixelKit.
//
// Legacy `Pixel` built a name as `<name><frequencySuffix>` and `URL.makePixelURL` then appended
// `_ios_<formFactor>`. `namePrefix: .none` plus `platformSuffixPolicy: .standard` reproduces exactly
// that. Migrated pixels keep the names they shipped with.
//
// `Pixel.Event` itself is unchanged: it stays the catalogue of legacy pixel names. Only the way it
// reaches the network moves.
//
// # Migrating a call site
//
// Frequency comes from the legacy call shape:
//
//     Legacy call                                                          PixelKit frequency
//     ------------------------------------------------------------------   ----------------------
//     Pixel.fire(pixel:)                                                   .standard
//     Pixel.fire(pixel:debounce: n)                                        .debounce(seconds: n)
//     DailyPixel.fire(pixel:)                                              .legacyDailyNoSuffix
//     DailyPixel.fireDailyAndCount(pixel:)            "_daily" / "_count"  .dailyAndCount
//       …(pixelNameSuffixes: .legacyDailyPixelSuffixes)   "_d" / "_c"      .legacyDailyAndCount
//       …(pixelNameSuffixes: .dailyAndStandardSuffixes)   "_daily" / ""    .dailyAndStandard
//     UniquePixel.fire(pixel:)   name ends "_u"                            .uniqueByName
//     UniquePixel.fire(pixel:)   name ends "_unique"                       .legacyInitial
//     persistentPixel.fire(…)                                              .standard  + .withRetry
//     persistentPixel.fireDailyAndCount(…)                        matching daily freq + .withRetry
//
// `_unique` names must use `.legacyInitial`, not `.uniqueByName`. PixelKit's `.uniqueByName` guards
// on a `_u` suffix and returns *without firing* when it is absent. A `_unique` pixel routed there
// would silently stop being sent. Both frequencies throttle under the same storage key, so their
// once-ever state is shared and migrated together.
//
// Parameters and transport come from the legacy arguments:
//
//     Legacy argument                                    PixelKit
//     ------------------------------------------------   -------------------------------------
//     withAdditionalParameters: p                        options: .parameters(p)
//     includedParameters: [.appVersion]   (the default)  options: .default
//     includedParameters: []                             options: .withoutAppVersion
//     includedParameters: [.appVersion, .atb]            options: .withATB
//     includedParameters: [.isInternalUser]              dropped: no call site ever passed it
//     error: e                                            event.withError(e)
//     withHeaders: h                                     Options.headers
//     allowedQueryReservedCharacters: c                  Options.allowedQueryReservedCharacters
//     onComplete: { … }                                  fireAsync, or dropped
//     forDeviceType: nil                                 event.withoutPlatformSuffix
//
// Two legacy statics have PixelKit equivalents rather than wrappers here:
// `UniquePixel.cohort(from:)` becomes `PixelKit.cohort(from:)`, and
// `Pixel.Event.lastFireDate(uniquePixelStorage:)` becomes `PixelKit.pixelLastFireDate(event:frequency:)`.

extension Pixel.Event: PixelKit.Event {

    /// Legacy names are complete: `Pixel` never prefixed them.
    public var namePrefix: PixelKitNamePrefix { .none }

    /// Legacy `Pixel` appended `_ios_<formFactor>` after any frequency suffix the caller had already
    /// baked into the name. `.standard` reproduces that order.
    ///
    /// It also keeps the platform marker out of PixelKit's throttling key. That is what lets the
    /// once-ever and once-daily state carry over from the legacy stores. See
    /// `LegacyPixelStateMigration`.
    public var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .standard }

    /// Always `nil`. Legacy `Pixel.Event` carried no parameters of its own; they came from the call site.
    public var parameters: [String: String]? { nil }

    public var standardParameters: [PixelKitStandardParameter]? { nil }

    /// Declared explicitly rather than left to the protocol's reflection-based default, which would
    /// pick up any `NSError` associated value on a case. Legacy `Pixel` only ever attached the error
    /// passed to `fire`. An error reaches PixelKit only through `withError(_:)`.
    public var error: NSError? { nil }
}

public extension Pixel.Event {

    /// This event with `error` attached. PixelKit then adds the same error parameters legacy
    /// `Pixel.fire(pixel:error:)` added. A `nil` error yields an event with no error, matching
    /// what the legacy optional `error:` argument did.
    func withError(_ error: Error?) -> PixelKit.Event {
        LegacyPixelEventWithError(wrapped: self, error: error as NSError?)
    }

    /// This event with no platform marker, reproducing legacy `Pixel.fire(pixel:forDeviceType: nil)`.
    var withoutPlatformSuffix: PixelKit.Event {
        LegacyPixelEventWithoutPlatformSuffix(wrapped: self)
    }
}

/// A pixel identified by a raw name rather than by a `Pixel.Event` case, reproducing legacy
/// `Pixel.fire(pixelNamed:)`.
public struct LegacyNamedPixel: PixelKit.Event {
    public let name: String
    public let namePrefix: PixelKitNamePrefix = .none
    public let platformSuffixPolicy: PixelKitPlatformSuffixPolicy = .standard
    public let parameters: [String: String]? = nil
    public let standardParameters: [PixelKitStandardParameter]? = nil
    public let error: NSError? = nil

    public init(name: String) {
        self.name = name
    }
}

/// See `Pixel.Event.withError(_:)`.
private struct LegacyPixelEventWithError: PixelKit.Event {
    let wrapped: Pixel.Event
    /// Declared so the reflection-based default inspects nothing: this is the error, stated outright.
    let error: NSError?

    var name: String { wrapped.name }
    var namePrefix: PixelKitNamePrefix { wrapped.namePrefix }
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { wrapped.platformSuffixPolicy }
    var parameters: [String: String]? { wrapped.parameters }
    var standardParameters: [PixelKitStandardParameter]? { wrapped.standardParameters }
}

/// See `Pixel.Event.withoutPlatformSuffix`.
private struct LegacyPixelEventWithoutPlatformSuffix: PixelKit.Event {
    let wrapped: Pixel.Event

    var name: String { wrapped.name }
    var namePrefix: PixelKitNamePrefix { wrapped.namePrefix }
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyOmitted }
    var parameters: [String: String]? { wrapped.parameters }
    var standardParameters: [PixelKitStandardParameter]? { wrapped.standardParameters }
    var error: NSError? { wrapped.error }
}
