//
//  MacOSEventHubPixelFiring.swift
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

import Common
import EventHub
import Foundation
import os.log
import PixelKit

/// The macOS platform marker EventHub appends itself, rather than letting PixelKit derive one.
private let macOSSuffix = "_macos"

/// The PixelKit event shape shared by both EventHub pixel paths on macOS — telemetry and the failure
/// events below. Deliberately *not* wrapped in `DebugEvent` for the failure path: PixelKit rewrites an
/// unprefixed `DebugEvent` to `m_mac_debug_<name>`, which would undo the naming these pixels need.
private struct EventHubPixelKitEvent: PixelKitEvent {
    let name: String
    let parameters: [String: String]?
    let standardParameters: [PixelKitStandardParameter]? = nil
    /// Declared explicitly rather than left to `PixelKitEvent`'s reflection-based default, which would
    /// find nothing on a struct whose error is not an associated value.
    let error: NSError?
}

/// Fires EventHub-originated pixels through PixelKit, appending the macOS platform suffix per the
/// Tech Design's platform-suffix split (`EventHub` itself fires the bare governed config name).
struct MacOSEventHubPixelFiring: EventHubPixelFiring {

    func enqueueFirePixel(named name: String, parameters: [String: String]) {
        let pixelName = name + macOSSuffix
        Logger.eventHub.info("PixelKit fire: \(pixelName, privacy: .public) \(parameters, privacy: .public)")
        // `doNotEnforcePrefix` is required: these names already carry the `_macos` platform suffix, and
        // without it PixelKit prepends `m_mac_` to any macOS name that lacks that prefix — which would
        // both double the platform marker and diverge from the names declared in event_hub.json5.
        PixelKit.fire(EventHubPixelKitEvent(name: pixelName, parameters: parameters, error: nil),
                      doNotEnforcePrefix: true)
    }
}

/// Reports EventHub's own failures (`EventHubDebugEvent`) as PixelKit error pixels, under the same naming
/// rules as the telemetry above — `EventHubDebugEvent.pixelName` supplies the shared base name, to which
/// this appends the same `_macos` marker.
final class MacOSEventHubDebugEventMapping: EventMapping<EventHubDebugEvent> {

    init() {
        super.init { event, error, _, _ in
            let pixelName = event.pixelName + macOSSuffix
            Logger.eventHub.error("PixelKit fire: \(pixelName, privacy: .public) \(event.pixelParameters, privacy: .public)")
            // `.dailyAndCount`, unlike the telemetry path: these fire from failures that repeat on every
            // attempt — a store that cannot write fails again at each flush — so the daily pixel bounds
            // how many users are affected while the count keeps the rate visible.
            PixelKit.fire(EventHubPixelKitEvent(name: pixelName,
                                                parameters: event.pixelParameters,
                                                error: error.map { $0 as NSError }),
                          frequency: .dailyAndCount,
                          doNotEnforcePrefix: true)
        }
    }

    override init(mapping: @escaping EventMapping<EventHubDebugEvent>.Mapping) {
        fatalError("Use init()")
    }
}
