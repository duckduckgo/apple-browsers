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

/// The PixelKit event shape shared by both EventHub pixel paths on iOS — telemetry and the failure events
/// below. See `IOSEventHubPixelFiring`'s doc comment for why the empty `namePrefix` is what produces the
/// names `event_hub.json5` declares.
private struct EventHubPixelKitEvent: PixelKit.Event, PixelKitEventWithCustomPrefix {
    let namePrefix = ""
    let name: String
    let parameters: [String: String]?
    let standardParameters: [PixelKitStandardParameter]? = nil
    /// Declared explicitly rather than left to `PixelKit.Event`'s reflection-based default, which would
    /// find nothing on a struct whose error is not an associated value.
    let error: NSError?
}

/// Fires EventHub-originated pixels through PixelKit, appending iOS' platform and form-factor markers per
/// the Tech Design's platform-suffix split (`EventHub` itself fires the bare governed config name).
///
/// The conformance to `PixelKitEventWithCustomPrefix` with an **empty** `namePrefix` is deliberate, and is
/// the only combination that produces the name `event_hub.json5` declares. `PixelKit`'s name resolution
/// has three relevant paths:
///
/// - no `PixelKitEventWithCustomPrefix`: on iOS the name is returned untouched, so it would carry no
///   platform or form-factor marker at all and would not match the declared `platform`/`form_factor`
///   suffixes.
/// - `PixelKitEventWithCustomPrefix` with the conventional `"m_"` prefix (what `WideEventFailureEvent`
///   uses): appends the platform suffix but reintroduces the legacy `m_` prefix these names must not have.
/// - `PixelKitEventWithCustomPrefix` with `""`: appends `platformSuffix` (`_ios_phone` / `_ios_tablet`,
///   derived from the `source` given to `PixelKit.setUp`) and prepends nothing. This is what we want.
struct IOSEventHubPixelFiring: EventHubPixelFiring {

    func enqueueFirePixel(named name: String, parameters: [String: String]) {
        // The governed name, without the platform suffix PixelKit appends when it builds the request.
        Logger.eventHub.info("PixelKit fire: \(name, privacy: .public) \(parameters, privacy: .private)")
        // `frequency` stays `.standard`: EventHub has already done the period aggregation, so PixelKit
        // must not apply a second layer of daily de-duplication on top of it.
        PixelKit.fire(EventHubPixelKitEvent(name: name, parameters: parameters, error: nil))
    }
}

/// Reports EventHub's own failures (`EventHubDebugEvent`) as PixelKit error pixels, under the same naming
/// rules as the telemetry above — `EventHubDebugEvent.pixelName` supplies the shared base name and PixelKit
/// appends the platform marker.
final class IOSEventHubDebugEventMapping: EventMapping<EventHubDebugEvent> {

    init() {
        super.init { event, error, _, _ in
            Logger.eventHub.error("PixelKit fire: \(event.pixelName, privacy: .public) \(event.pixelParameters, privacy: .private)")
            // `.dailyAndCount`, unlike the telemetry path: these fire from failures that repeat on every
            // attempt — a store that cannot write fails again at each flush — so the daily pixel bounds
            // how many users are affected while the count keeps the rate visible.
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
