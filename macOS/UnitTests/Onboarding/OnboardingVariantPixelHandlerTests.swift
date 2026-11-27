//
//  OnboardingVariantPixelHandlerTests.swift
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

import Onboarding
import Persistence
import Testing

@testable import DuckDuckGo_Privacy_Browser

@available(iOS 16, macOS 13, *)
@Suite("Onboarding variant pixel handler")
struct OnboardingVariantPixelHandlerTests {

    private let recorder = RecordingOnboardingSharedPixelHandler()
    private let handler: OnboardingVariantPixelHandler

    init() {
        handler = OnboardingVariantPixelHandler(handler: recorder, settings: InMemoryKeyValueStore().keyedStoring())
    }

    @Test("Pixels before the search or chat choice carry no variant", .timeLimit(.minutes(1)))
    func pixelsBeforeChoiceCarryNoVariant() {
        handler.fire(.searchExperience(.shown))
        handler.fire(.searchChatToggle(.shown))

        #expect(recorder.searchExperienceVariants == [nil, nil])
    }

    @Test("Pixels after the choice carry it, but not the choice's own click",
          .timeLimit(.minutes(1)),
          arguments: [
            (OnboardingSharedPixelEvent.SuggestionOrCustomToggleEvent.Value.customChat, OnboardingPixelParameter.SearchExperienceVariant.duckAIChat),
            (.suggestedChat, .duckAIChat),
            (.customSearch, .duckAISearch),
            (.suggestedSearch, .duckAISearch)
          ])
    func pixelsAfterChoiceCarryVariant(value: OnboardingSharedPixelEvent.SuggestionOrCustomToggleEvent.Value,
                                       variant: OnboardingPixelParameter.SearchExperienceVariant) {
        handler.fire(.searchChatToggle(.clicked(value)))
        handler.fire(.fireButton(.shown))

        #expect(recorder.searchExperienceVariants == [nil, variant])
    }

    @Test("The first choice is kept", .timeLimit(.minutes(1)))
    func firstChoiceIsKept() {
        handler.fire(.searchChatToggle(.clicked(.customChat)))
        handler.fire(.searchChatToggle(.clicked(.customSearch)))
        handler.fire(.end(.shown))

        #expect(recorder.searchExperienceVariants.last == .duckAIChat)
    }

    @Test("The choice outlives the handler that recorded it", .timeLimit(.minutes(1)))
    func choiceIsStored() {
        let settings: any KeyedStoring<OnboardingPixelSettings> = InMemoryKeyValueStore().keyedStoring()
        OnboardingVariantPixelHandler(handler: recorder, settings: settings).fire(.searchChatToggle(.clicked(.suggestedChat)))

        OnboardingVariantPixelHandler(handler: recorder, settings: settings).fire(.end(.shown))

        #expect(recorder.searchExperienceVariants.last == .duckAIChat)
    }
}

private final class RecordingOnboardingSharedPixelHandler: OnboardingSharedPixelHandling {
    private(set) var searchExperienceVariants: [OnboardingPixelParameter.SearchExperienceVariant?] = []

    func fire(_ event: OnboardingSharedPixelEvent,
              source: OnboardingPixelParameter.Source?,
              flow: OnboardingPixelParameter.Flow?,
              variants: OnboardingPixelParameter.Variants) {
        searchExperienceVariants.append(variants.searchExperience)
    }
}
