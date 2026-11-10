//
//  AIChatPreferencesPageSummariesTests.swift
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
import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Ask About Page Summaries setting")
final class AIChatPreferencesPageSummariesTests {

    private let engine = StubLocalModelEngine()
    private let storage = MockAIChatPreferencesStorage()
    private let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLocalModels.rawValue: true])
    private var setupDialogPresentations = 0

    private lazy var service = AIChatLocalModelService(featureFlagger: featureFlagger,
                                                       storage: storage,
                                                       engine: engine,
                                                       notificationCenter: NotificationCenter())

    private func makePreferences() -> AIChatPreferences {
        AIChatPreferences(storage: storage,
                          aiChatMenuConfiguration: MockAIChatConfig(),
                          windowControllersManager: WindowControllersManagerMock(),
                          featureFlagger: featureFlagger,
                          localModelService: service,
                          presentAppleIntelligenceSetup: { [weak self] in self?.setupDialogPresentations += 1 })
    }

    @available(iOS 16, macOS 13, *)
    @Test("The setting shows only with the flag on", .timeLimit(.minutes(1)))
    func visibleOnlyWithTheFlag() {
        let preferences = makePreferences()
        #expect(preferences.shouldShowPageSummariesSetting)

        featureFlagger.featuresStub = [:]
        #expect(!preferences.shouldShowPageSummariesSetting)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Choosing Apple Intelligence opts in when it's available", .timeLimit(.minutes(1)))
    func choosingAppleIntelligenceOptsIn() {
        let preferences = makePreferences()

        preferences.pageSummariesModelBinding.wrappedValue = .appleIntelligence

        #expect(preferences.pageSummariesModel == .appleIntelligence)
        #expect(storage.pageSummariesModel == .appleIntelligence)
        #expect(setupDialogPresentations == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Choosing Apple Intelligence when it isn't set up shows the setup dialog and keeps Duck.ai",
          .timeLimit(.minutes(1)),
          arguments: [AIChatLocalModelAvailability.appleIntelligenceNotEnabled, .modelNotReady])
    func choosingAppleIntelligenceWhenUnavailableShowsDialog(availability: AIChatLocalModelAvailability) {
        engine.availability = availability
        let preferences = makePreferences()

        preferences.pageSummariesModelBinding.wrappedValue = .appleIntelligence

        #expect(setupDialogPresentations == 1)
        #expect(preferences.pageSummariesModel == .duckAI)
        #expect(storage.pageSummariesModel == .duckAI)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The availability check is fresh, so turning Apple Intelligence on in System Settings is picked up",
          .timeLimit(.minutes(1)))
    func availabilityIsCheckedOnEachChoice() {
        engine.availability = .appleIntelligenceNotEnabled
        let preferences = makePreferences()
        preferences.pageSummariesModelBinding.wrappedValue = .appleIntelligence

        engine.availability = .available
        preferences.pageSummariesModelBinding.wrappedValue = .appleIntelligence

        #expect(setupDialogPresentations == 1)
        #expect(storage.pageSummariesModel == .appleIntelligence)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Choosing Duck.ai Models opts out", .timeLimit(.minutes(1)))
    func choosingDuckAIOptsOut() {
        storage.pageSummariesModel = .appleIntelligence
        let preferences = makePreferences()

        preferences.pageSummariesModelBinding.wrappedValue = .duckAI

        #expect(storage.pageSummariesModel == .duckAI)
    }
}
