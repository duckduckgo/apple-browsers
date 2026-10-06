//
//  EventHubPixelFiring.swift
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

/// A fired telemetry pixel: the bare governed config name (e.g. `webTelemetry_adwalls_day`) with no
/// platform suffix — per the Tech Design, the platform-specific `EventHubPixelFiring` conformance is
/// responsible for the suffix (iOS `_ios_phone`/`_ios_tablet`, macOS `_macos`), not `EventHub` itself.
public struct FiredPixel: Equatable, Sendable {
    public let name: String
    public let parameters: [String: String]

    public init(name: String, parameters: [String: String]) {
        self.name = name
        self.parameters = parameters
    }
}

/// Injected pixel-firing seam. Both iOS and macOS app targets provide a `PixelKit`-based conformance
/// (out of scope for this package) that appends their platform suffix before firing.
public protocol EventHubPixelFiring {
    func enqueueFirePixel(named name: String, parameters: [String: String])
}
