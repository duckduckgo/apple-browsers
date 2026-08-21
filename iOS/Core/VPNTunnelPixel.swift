//
//  VPNTunnelPixel.swift
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

/// Bridges an iOS `Pixel.Event` to a `PixelKitEvent` so VPN packet-tunnel pixels can be
/// fired through `PixelKit` while preserving their existing base names and frequency suffixes.
///
/// iOS `Pixel.Event.name` values already carry their full prefix (e.g. `m_netp_…`). On iOS,
/// `PixelKit` does not prepend a prefix (see `prefixedAndSuffixedName`), so delegating `name`
/// to `Pixel.Event.name` preserves the base name, and the frequency appends the `_d`/`_c`
/// suffixes as before. This intentionally removes the legacy `_ios_phone` / `_ios_tablet`
/// form-factor suffix. Using `Pixel.Event` as the single source of truth means base names cannot
/// drift during migration.
///
/// The error, when present, is carried on the event and encoded by `PixelKit` into the
/// standard `e`/`d`/`ue`/`ud` parameters — matching the legacy error parameters.
public struct VPNTunnelPixel: PixelKitEvent {

    private let event: Pixel.Event
    private let underlyingError: Error?

    public init(_ event: Pixel.Event, error: Error? = nil) {
        self.event = event
        self.underlyingError = error
    }

    public var name: String {
        event.name
    }

    public var parameters: [String: String]? {
        nil
    }

    public var standardParameters: [PixelKitStandardParameter]? {
        nil
    }

    public var error: NSError? {
        underlyingError as NSError?
    }
}

public extension PixelKit {

    /// Fires a VPN packet-tunnel pixel through `PixelKit` as a daily-and-count pixel,
    /// replacing `DailyPixel.fireDailyAndCount(…, pixelNameSuffixes: .legacyDailyPixelSuffixes)`
    /// and `persistentPixel.fireDailyAndCount(…)`. `.legacyDailyAndCount` reproduces the `_d`/`_c`
    /// suffixes; callers can preserve persistence by opting into PixelKit's retry queue.
    static func fireVPNTunnel(dailyAndCount event: Pixel.Event,
                              error: Error? = nil,
                              retryOnFailure: Bool = false,
                              withAdditionalParameters params: [String: String] = [:]) {
        shared?.fireVPNTunnel(dailyAndCount: event,
                              error: error,
                              retryOnFailure: retryOnFailure,
                              withAdditionalParameters: params)
    }

    /// Fires a VPN packet-tunnel pixel through `PixelKit` as a once-per-day pixel with no added
    /// suffix, replacing `DailyPixel.fire(…)`. The event name is emitted verbatim (matching the
    /// legacy behaviour where the name already carries any `_d` suffix).
    static func fireVPNTunnel(daily event: Pixel.Event,
                              withAdditionalParameters params: [String: String] = [:]) {
        fire(VPNTunnelPixel(event),
             frequency: .legacyDailyNoSuffix,
             withAdditionalParameters: params)
    }

    /// Fires a VPN packet-tunnel pixel through `PixelKit` on every call, replacing `Pixel.fire(…)`.
    static func fireVPNTunnel(standard event: Pixel.Event,
                              error: Error? = nil,
                              withAdditionalParameters params: [String: String] = [:]) {
        fire(VPNTunnelPixel(event, error: error),
             frequency: .standard,
             withAdditionalParameters: params)
    }
}

extension PixelKit {

    func fireVPNTunnel(dailyAndCount event: Pixel.Event,
                       error: Error? = nil,
                       retryOnFailure: Bool = false,
                       withAdditionalParameters params: [String: String] = [:]) {
        fire(VPNTunnelPixel(event, error: error),
             frequency: .legacyDailyAndCount,
             options: Options(additionalParameters: params, retryOnFailure: retryOnFailure))
    }
}
