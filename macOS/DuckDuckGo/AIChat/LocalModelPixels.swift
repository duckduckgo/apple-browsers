//
//  LocalModelPixels.swift
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

import AIChat
import PixelKit

struct LocalModelPixelEvent: PixelKit.Event {
    let pixel: AIChatLocalModelPixel

    var name: String { pixel.name + "_macos" }
    var parameters: [String: String]? { pixel.parameters }
    var standardParameters: [PixelKitStandardParameter]? { nil }
    var namePrefix: PixelKitNamePrefix { .none }
}

final class LocalModelPixelInstrumentation: AIChatLocalModelInstrumentation {

    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func fire(_ pixel: AIChatLocalModelPixel) {
        pixelFiring?.fire(LocalModelPixelEvent(pixel: pixel), frequency: pixel.frequency.pixelKitFrequency)
    }
}

extension AIChatLocalModelPixel.Frequency {

    var pixelKitFrequency: PixelKit.Frequency {
        switch self {
        case .standard: return .standard
        case .daily: return .daily
        case .dailyAndCount: return .dailyAndCount
        }
    }
}
