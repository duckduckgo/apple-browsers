//
//  IOSEventHubPixelFiring.swift
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

import Common
import EventHub
import Foundation
import os.log
import PixelKit

/// PixelKit event for EventHub-originated pixels, shared by the telemetry and failure paths below.
private struct EventHubPixelKitEvent: PixelKit.Event {
    /// Frozen: matches the suffix order declared in `event_hub.json5`.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyBeforeFrequencySuffix }

    /// No prefix: names come fully formed from `event_hub.json5`.
    let namePrefix: PixelKitNamePrefix = .none
    let name: String
    let parameters: [String: String]?
    let standardParameters: [PixelKitStandardParameter]? = nil
    /// Declared explicitly: the reflection-based default finds nothing on a struct whose error is
    /// not an associated value.
    let error: NSError?
}

/// Fires EventHub telemetry pixels through PixelKit.
struct IOSEventHubPixelFiring: EventHubPixelFiring {

    func enqueueFirePixel(named name: String, parameters: [String: String]) {
        Logger.eventHub.info("PixelKit fire: \(name, privacy: .public) \(parameters, privacy: .private)")
        PixelKit.fire(EventHubPixelKitEvent(name: name, parameters: parameters, error: nil))
    }
}

/// Reports `EventHubDebugEvent` failures as PixelKit pixels.
final class IOSEventHubDebugEventMapping: EventMapping<EventHubDebugEvent> {

    init() {
        super.init { event, error, _, _ in
            Logger.eventHub.error("PixelKit fire: \(event.pixelName, privacy: .public) \(event.pixelParameters, privacy: .private)")
            PixelKit.fire(EventHubPixelKitEvent(name: event.pixelName,
                                                parameters: event.pixelParameters,
                                                error: error.map { $0 as NSError }),
                          frequency: .dailyAndCount)
        }
    }

    override init(mapping: @escaping EventMapping<EventHubDebugEvent>.Mapping) {
        fatalError("Use init()")
    }
}
