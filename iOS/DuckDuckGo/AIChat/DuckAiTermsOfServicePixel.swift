//
//  DuckAiTermsOfServicePixel.swift
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

import AIChat
import os.log
import PixelKit

/// The Duck.ai Terms of Service disclaimer's pixels, named by the shared measurement.
struct DuckAiTermsOfServicePixel: PixelKit.Event {
    let name: String
    let parameters: [String: String]?
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// The surface is read per fire, since one UTI coordinator serves the address bar, the Duck.ai tab and
/// the contextual sheet. `nil` for the web's acceptance.
struct DuckAiTermsOfServicePixelAdapter: DuckAiTermsOfServicePixelFiring {

    private let firing: UTIPixelFiring
    private let surface: () -> UnifiedToggleInputPixelSurface?

    init(firing: UTIPixelFiring = .live, surface: @escaping () -> UnifiedToggleInputPixelSurface?) {
        self.firing = firing
        self.surface = surface
    }

    func fire(_ event: DuckAiTermsOfServiceMeasurementEvent) {
        let pixel = DuckAiTermsOfServicePixel(name: event.pixelName, parameters: event.pixelParameters(surface: surface()?.rawValue))
        Logger.aiChat.debug("[TermsOfService] pixel \(pixel.name, privacy: .public) \(String(describing: pixel.parameters), privacy: .public)")
        firing.fire(pixel, frequency: .dailyAndCount)
    }
}

extension DuckAiTermsOfServiceSendMethod {

    init(trigger: TextSubmissionTrigger) {
        switch trigger {
        case .sendButton: self = .ask
        case .textEntry: self = .return
        case .programmatic: self = .quickAction
        }
    }
}
