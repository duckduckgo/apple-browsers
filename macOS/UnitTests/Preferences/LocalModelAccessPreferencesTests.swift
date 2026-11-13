//
//  LocalModelAccessPreferencesTests.swift
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
import Combine
import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Local Model Access setting")
final class LocalModelAccessPreferencesTests {

    private let engine = StubLocalModelEngine()
    private let storage = MockAIChatPreferencesStorage()
    private let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLocalModels.rawValue: true])
    private var confirms = true
    private var confirmations = 0
    private var redraws = 0

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
                          confirmLocalModelTurnOn: { [weak self] in
                              guard let self else { return false }
                              confirmations += 1
                              return confirms
                          })
    }

    @available(iOS 16, macOS 13, *)
    @Test("The section shows only with the flag on", .timeLimit(.minutes(1)))
    func visibleOnlyWithTheFlag() {
        let preferences = makePreferences()
        #expect(preferences.shouldShowLocalModelAccess)

        featureFlagger.featuresStub = [:]
        #expect(!preferences.shouldShowLocalModelAccess)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The section shows only where Apple Intelligence is ready",
          .timeLimit(.minutes(1)),
          arguments: [
            (AIChatLocalModelAvailability.available, true),
            (.appleIntelligenceNotEnabled, false),
            (.modelNotReady, false),
            (.deviceNotEligible, false),
            (.unsupportedOS, false)
          ])
    func visibleOnlyWhereAppleIntelligenceIsReady(availability: AIChatLocalModelAvailability, isShown: Bool) {
        engine.availability = availability

        #expect(makePreferences().shouldShowLocalModelAccess == isShown)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The pane redraws when Apple Intelligence is turned on in System Settings", .timeLimit(.minutes(1)))
    func redrawsOnAvailabilityChanges() async {
        engine.availability = .appleIntelligenceNotEnabled
        let preferences = makePreferences()
        preferences.observeLocalModelAvailability()
        #expect(!preferences.shouldShowLocalModelAccess)
        let cancellable = preferences.objectWillChange.sink { [weak self] in self?.redraws += 1 }

        engine.availability = .available
        service.refreshAvailability()
        await waitUntil { self.redraws > 0 }

        #expect(redraws > 0)
        #expect(preferences.shouldShowLocalModelAccess)
        cancellable.cancel()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turn On asks first, then turns the model on", .timeLimit(.minutes(1)))
    func turnOnAfterConfirming() async {
        let preferences = makePreferences()

        await preferences.turnOnLocalModel()

        #expect(confirmations == 1)
        #expect(preferences.isLocalModelOn)
        #expect(storage.pageSummariesModel == .appleIntelligence)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancel leaves the model off", .timeLimit(.minutes(1)))
    func cancelLeavesItOff() async {
        confirms = false
        let preferences = makePreferences()

        await preferences.turnOnLocalModel()

        #expect(!preferences.isLocalModelOn)
        #expect(storage.pageSummariesModel == .duckAI)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turn Off turns the model off without asking", .timeLimit(.minutes(1)))
    func turnOffWithoutAsking() {
        storage.pageSummariesModel = .appleIntelligence
        let preferences = makePreferences()
        #expect(preferences.isLocalModelOn)

        preferences.turnOffLocalModel()

        #expect(confirmations == 0)
        #expect(storage.pageSummariesModel == .duckAI)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}
