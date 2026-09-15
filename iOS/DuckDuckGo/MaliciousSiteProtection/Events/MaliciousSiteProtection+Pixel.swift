//
//  MaliciousSiteProtection+Pixel.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Core
import MaliciousSiteProtection
import PixelKit

extension Pixel {

    static func fire(_ event: MaliciousSiteProtection.Event) {
        guard let convertedPixelEvent = Event.MaliciousSiteProtectionEvent(event) else { return }
        PixelKit.fire(Pixel.Event.maliciousSiteProtection(event: convertedPixelEvent), options: .parameters(convertedPixelEvent.parameters))
    }

    static func fireDailyAndCount(_ event: MaliciousSiteProtection.Event) {
        guard let convertedPixelEvent = Event.MaliciousSiteProtectionEvent(event) else { return }
        PixelKit.fire(Pixel.Event.maliciousSiteProtection(event: convertedPixelEvent), frequency: .dailyAndCount, options: .parameters(convertedPixelEvent.parameters))
    }

    static func fireDailyAndStandard(_ event: MaliciousSiteProtection.Event) {
        guard let convertedPixelEvent = Event.MaliciousSiteProtectionEvent(event) else { return }
        PixelKit.fire(Pixel.Event.maliciousSiteProtection(event: convertedPixelEvent), frequency: .dailyAndStandard, options: .parameters(convertedPixelEvent.parameters))
    }

}
