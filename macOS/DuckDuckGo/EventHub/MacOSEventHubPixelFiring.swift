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

import EventHub
import Foundation
import os.log
import PixelKit

/// Fires EventHub-originated pixels through PixelKit, appending the macOS platform suffix per the
/// Tech Design's platform-suffix split (`EventHub` itself fires the bare governed config name).
struct MacOSEventHubPixelFiring: EventHubPixelFiring {

    private struct Event: PixelKitEvent {
        let name: String
        let parameters: [String: String]?
        let standardParameters: [PixelKitStandardParameter]? = nil
    }

    func enqueueFirePixel(named name: String, parameters: [String: String]) {
        let pixelName = "\(name)_macos"
        Logger.eventHub.info("PixelKit fire: \(pixelName, privacy: .public) \(parameters, privacy: .public)")
        PixelKit.fire(Event(name: pixelName, parameters: parameters))
    }
}
