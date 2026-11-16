//
//  AIChatPromptLimitsPrivacyConfigTests.swift
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

import Foundation
import Testing
@testable import AIChat

struct AIChatPromptLimitsPrivacyConfigTests {

    private let fallback = AIChatPromptLimits.current

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [nil, "", "not json", "{}", "[]"] as [String?])
    func missingSettingsUseTheFallback(_ json: String?) {
        #expect(AIChatPromptLimits(settingsJSON: json) == fallback)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bothValuesAreRead() {
        let limits = AIChatPromptLimits(settingsJSON: #"{"pasteConversionThreshold": 2000, "maxCharacters": 8000}"#)
        #expect(limits == AIChatPromptLimits(maxCharacters: 8_000, pasteConversionThreshold: 2_000))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func eachMissingValueFallsBackOnItsOwn() {
        #expect(AIChatPromptLimits(settingsJSON: #"{"pasteConversionThreshold": 3000}"#)
                == AIChatPromptLimits(maxCharacters: fallback.maxCharacters, pasteConversionThreshold: 3_000))
        #expect(AIChatPromptLimits(settingsJSON: #"{"maxCharacters": 20000}"#)
                == AIChatPromptLimits(maxCharacters: 20_000, pasteConversionThreshold: fallback.pasteConversionThreshold))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func invalidValuesFallBack() {
        #expect(AIChatPromptLimits(settingsJSON: #"{"pasteConversionThreshold": 0, "maxCharacters": -1}"#) == fallback)
        #expect(AIChatPromptLimits(settingsJSON: #"{"pasteConversionThreshold": "4000", "maxCharacters": 12.5}"#) == fallback)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func thresholdAboveTheMaximumFallsBackEntirely() {
        #expect(AIChatPromptLimits(settingsJSON: #"{"pasteConversionThreshold": 9000, "maxCharacters": 8000}"#) == fallback)
        #expect(AIChatPromptLimits(settingsJSON: #"{"maxCharacters": 3000}"#) == fallback)
    }
}
