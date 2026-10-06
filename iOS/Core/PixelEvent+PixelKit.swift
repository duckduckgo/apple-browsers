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

// Fires `Pixel.Event` through PixelKit, preserving every pixel's legacy wire name. See
// `PixelEvent+PixelKit.md` for why that works and for the call-site migration reference tables.

extension Pixel.Event: PixelKit.Event {

    /// Legacy names are complete: `Pixel` never prefixed them.
    public var namePrefix: PixelKitNamePrefix { .none }

    /// Legacy `Pixel` appended `_ios_<formFactor>` after any frequency suffix the caller had already
    /// baked into the name. `.standard` reproduces that order.
    ///
    /// It also keeps the platform marker out of PixelKit's throttling key, which is what lets the
    /// once-ever and once-daily state carry over from the legacy stores. See
    /// `LegacyPixelStateMigration`.
    public var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .standard }

    /// Several legacy names interpolate a bucketed value such as `0.5`, so they contain a `.`.
    /// They shipped that way and the metric depends on the exact name.
    public var allowsDotInName: Bool { true }

    /// Always `nil`: legacy `Pixel.Event` carried no parameters of its own, they came from the call site.
    public var parameters: [String: String]? { nil }

    public var standardParameters: [PixelKitStandardParameter]? { nil }

    /// Declared explicitly rather than left to the protocol's reflection-based default, which would
    /// pick up any `NSError` associated value on a case. Legacy `Pixel` only ever attached the error
    /// passed to `fire`, so an error reaches PixelKit through `withError(_:)` and nowhere else.
    public var error: NSError? { nil }
}

public extension Pixel.Event {

    /// This event carrying `error`, so PixelKit attaches the error parameters that legacy
    /// `Pixel.fire(pixel:error:)` attached. A `nil` error yields an event with no error, which is
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
    public let allowsDotInName: Bool = true
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
    var allowsDotInName: Bool { wrapped.allowsDotInName }
    var parameters: [String: String]? { wrapped.parameters }
    var standardParameters: [PixelKitStandardParameter]? { wrapped.standardParameters }
}

/// See `Pixel.Event.withoutPlatformSuffix`.
private struct LegacyPixelEventWithoutPlatformSuffix: PixelKit.Event {
    let wrapped: Pixel.Event

    var name: String { wrapped.name }
    var namePrefix: PixelKitNamePrefix { wrapped.namePrefix }
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyOmitted }
    var allowsDotInName: Bool { wrapped.allowsDotInName }
    var parameters: [String: String]? { wrapped.parameters }
    var standardParameters: [PixelKitStandardParameter]? { wrapped.standardParameters }
    var error: NSError? { wrapped.error }
}
