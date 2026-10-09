//
//  DuckAiInputOutcomePixel.swift
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

struct DuckAiInputOutcomePixel: PixelKit.Event {
    let parameters: [String: String]?
    var name: String { DuckAiInputOutcomeEvent.pixelName }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

struct DuckAiInputOutcomePixelAdapter: DuckAiInputOutcomePixelFiring {

    private let firing: UTIPixelFiring

    init(firing: UTIPixelFiring = .live) {
        self.firing = firing
    }

    func fire(_ event: DuckAiInputOutcomeEvent) {
        Logger.aiChat.debug("[InputOutcome] \(DuckAiInputOutcomeEvent.pixelName, privacy: .public) \(event.parameters, privacy: .public)")
        firing.fire(DuckAiInputOutcomePixel(parameters: event.parameters), frequency: .dailyAndCount)
    }
}

extension DuckAiInputSurface {

    init(_ surface: UnifiedToggleInputPixelSurface) {
        switch surface {
        case .addressBar: self = .addressBar
        case .duckAI: self = .duckAI
        case .contextualChat: self = .contextualChat
        }
    }
}

extension DuckAiInputSubmitMethod {

    init(trigger: TextSubmissionTrigger) {
        switch trigger {
        case .sendButton: self = .button
        case .textEntry: self = .enter
        case .pasteAndGo, .programmatic: self = .other
        }
    }
}
