//
//  UnifiedDeviceListPixelHandler.swift
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
import DDGSync
import Foundation
import class PixelKit.PixelKit
import enum PixelKit.PixelKitNamePrefix
import enum PixelKit.PixelKitStandardParameter
import protocol PixelKit.PixelFiring

private struct UnifiedDeviceListPixel: PixelKit.Event {
    let name: String
    let parameters: [String: String]?
    let standardParameters: [PixelKitStandardParameter]? = nil
    let error: NSError? = nil
    let namePrefix: PixelKitNamePrefix = .none
}

final class UnifiedDeviceListPixelHandler: EventMapping<UnifiedDeviceListEvent> {

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        super.init { event, _, _, onComplete in
            pixelFiring?.fire(
                UnifiedDeviceListPixel(name: event.name, parameters: event.parameters),
                frequency: event.frequency.pixelKitFrequency)
            onComplete(nil)
        }
    }

    override init(mapping: @escaping EventMapping<UnifiedDeviceListEvent>.Mapping) {
        fatalError("Use init()")
    }
}

private extension UnifiedDeviceListEvent.Frequency {
    var pixelKitFrequency: PixelKit.Frequency {
        switch self {
        case .standard: return .standard
        case .daily: return .daily
        }
    }
}
