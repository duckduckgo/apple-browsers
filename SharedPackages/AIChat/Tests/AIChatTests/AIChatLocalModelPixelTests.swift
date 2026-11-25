//
//  AIChatLocalModelPixelTests.swift
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

import Testing
@testable import AIChat

/// The names and values must match the pixel definitions on both platforms.
@Suite("Local model pixels")
struct AIChatLocalModelPixelTests {

    @available(iOS 16, macOS 13, *)
    @Test("The state pixel sends the choice, the state and why Apple Intelligence is missing", .timeLimit(.minutes(1)))
    func state() {
        let pixel = AIChatLocalModelPixel.state(selected: .appleIntelligence, state: .unsupported, availability: .appleIntelligenceNotEnabled)

        #expect(pixel.name == "aichat_local_model_state")
        #expect(pixel.parameters == ["selected": "system", "state": "unsupported", "system_model": "not_enabled"])
        #expect(pixel.frequency == .daily)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every availability has its own system_model value",
          .timeLimit(.minutes(1)),
          arguments: [(AIChatLocalModelAvailability.available, "available"),
                      (.appleIntelligenceNotEnabled, "not_enabled"),
                      (.modelNotReady, "not_ready"),
                      (.deviceNotEligible, "not_eligible"),
                      (.unsupportedOS, "unsupported_os")])
    func systemModel(availability: AIChatLocalModelAvailability, value: String) {
        let pixel = AIChatLocalModelPixel.state(selected: .duckAI, state: .notSetUp, availability: availability)

        #expect(pixel.parameters["system_model"] == value)
        #expect(pixel.parameters["selected"] == "cloud")
        #expect(pixel.parameters["state"] == "not_set_up")
    }

    @available(iOS 16, macOS 13, *)
    @Test("The prompt pixels name Duck.ai's prompt as the surface", .timeLimit(.minutes(1)))
    func prompt() {
        #expect(AIChatLocalModelPixel.promoShown.name == "aichat_local_model_promo_shown")
        #expect(AIChatLocalModelPixel.promoClosed.name == "aichat_local_model_promo_closed")
        #expect(AIChatLocalModelPixel.promoShown.parameters == ["surface": "duckai"])
        #expect(AIChatLocalModelPixel.promoClosed.parameters == ["surface": "duckai"])
        #expect(AIChatLocalModelPixel.promoShown.frequency == .dailyAndCount)
        #expect(AIChatLocalModelPixel.promoClosed.frequency == .dailyAndCount)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Selecting a model sends the engine and where it was chosen", .timeLimit(.minutes(1)))
    func selected() {
        let turnedOn = AIChatLocalModelPixel.selected(.appleIntelligence, source: .duckAIPromo)
        let turnedOff = AIChatLocalModelPixel.selected(.duckAI, source: .settings)

        #expect(turnedOn.name == "aichat_local_model_selected")
        #expect(turnedOn.parameters == ["engine": "system", "source": "duckai_promo"])
        #expect(turnedOff.parameters == ["engine": "cloud", "source": "settings"])
        #expect(turnedOn.frequency == .standard)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A run sends the engine and the task", .timeLimit(.minutes(1)))
    func runStarted() {
        let pixel = AIChatLocalModelPixel.runStarted(engine: .appleIntelligence, task: .title)

        #expect(pixel.name == "aichat_local_model_run_started")
        #expect(pixel.parameters == ["engine": "system", "task": "title"])
        #expect(pixel.frequency == .daily)
    }
}
