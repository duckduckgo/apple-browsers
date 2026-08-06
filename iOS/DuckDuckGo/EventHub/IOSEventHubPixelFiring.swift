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

import EventHub
import Foundation
import os.log
import PixelKit

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

    private struct Event: PixelKitEvent, PixelKitEventWithCustomPrefix {
        let namePrefix = ""
        let name: String
        let parameters: [String: String]?
        let standardParameters: [PixelKitStandardParameter]? = nil
    }

    func enqueueFirePixel(named name: String, parameters: [String: String]) {
        // The governed name, without the platform suffix PixelKit appends when it builds the request.
        Logger.eventHub.info("PixelKit fire: \(name, privacy: .public) \(parameters, privacy: .public)")
        // `frequency` stays `.standard`: EventHub has already done the period aggregation, so PixelKit
        // must not apply a second layer of daily de-duplication on top of it.
        PixelKit.fire(Event(name: name, parameters: parameters))
    }
}
