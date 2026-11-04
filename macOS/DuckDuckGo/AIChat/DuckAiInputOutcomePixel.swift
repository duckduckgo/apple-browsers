//
//  DuckAiInputOutcomePixel.swift
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

struct DuckAiInputOutcomePixel: PixelKit.Event {
    let parameters: [String: String]?
    var name: String { DuckAiInputOutcomeEvent.pixelName + "_macos" }
    var namePrefix: PixelKitNamePrefix { .none }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

struct DuckAiInputOutcomePixelAdapter: DuckAiInputOutcomePixelFiring {

    private let pixelFiring: PixelFiring?

    init(pixelFiring: PixelFiring? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    func fire(_ event: DuckAiInputOutcomeEvent) {
        Logger.aiChat.debug("[InputOutcome] \(DuckAiInputOutcomeEvent.pixelName, privacy: .public) \(event.parameters, privacy: .public)")
        pixelFiring?.fire(DuckAiInputOutcomePixel(parameters: event.parameters), frequency: .dailyAndCount)
    }
}
