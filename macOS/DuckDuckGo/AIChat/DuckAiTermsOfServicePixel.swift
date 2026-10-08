//
//  DuckAiTermsOfServicePixel.swift
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
import os.log
import PixelKit

/// The Duck.ai Terms of Service disclaimer's pixels, named by the shared measurement as on iOS.
struct DuckAiTermsOfServicePixel: PixelKit.Event {
    let name: String
    let parameters: [String: String]?
    var namePrefix: PixelKitNamePrefix { .none }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// One container VC serves the address bar and the Prompt Bar, so the surface is the one it was built
/// for. `nil` for the web's acceptance.
struct DuckAiTermsOfServicePixelAdapter: DuckAiTermsOfServicePixelFiring {

    private let surface: DuckAiUsageWarningPixelSurface?
    private let pixelFiring: PixelFiring?

    init(surface: DuckAiUsageWarningPixelSurface?, pixelFiring: PixelFiring? = PixelKit.shared) {
        self.surface = surface
        self.pixelFiring = pixelFiring
    }

    func fire(_ event: DuckAiTermsOfServiceMeasurementEvent) {
        let pixel = DuckAiTermsOfServicePixel(name: event.pixelName + "_macos", parameters: event.pixelParameters(surface: surface?.rawValue))
        Logger.aiChat.debug("[TermsOfService] pixel \(pixel.name, privacy: .public)")
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }
}
