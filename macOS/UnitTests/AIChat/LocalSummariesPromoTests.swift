//
//  LocalSummariesPromoTests.swift
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
@_spi(Testing) import Persistence
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Local summaries promo")
final class LocalSummariesPromoTests {

    private let engine = StubLocalModelEngine()
    private let storage = MockAIChatPreferencesStorage()
    private let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLocalModels.rawValue: true])
    private let keyValueStore = MockKeyValueFileStore()
    private let notificationCenter = NotificationCenter()

    private lazy var service = AIChatLocalModelService(featureFlagger: featureFlagger,
                                                       storage: storage,
                                                       engine: engine,
                                                       notificationCenter: notificationCenter)
    private lazy var promo = LocalSummariesPromo(localModelService: service,
                                                 keyValueStore: keyValueStore,
                                                 notificationCenter: notificationCenter)

    @available(iOS 16, macOS 13, *)
    @Test("Shows only with the flag on, Apple Intelligence ready, no opt-in and no earlier answer", .timeLimit(.minutes(1)))
    func eligibility() {
        #expect(LocalSummariesPromoEligibility.isEligible(isFeatureOn: true, availability: .available, isOptedIn: false, outcome: nil))

        #expect(!LocalSummariesPromoEligibility.isEligible(isFeatureOn: false, availability: .available, isOptedIn: false, outcome: nil))
        #expect(!LocalSummariesPromoEligibility.isEligible(isFeatureOn: true, availability: .appleIntelligenceNotEnabled, isOptedIn: false, outcome: nil))
        #expect(!LocalSummariesPromoEligibility.isEligible(isFeatureOn: true, availability: .modelNotReady, isOptedIn: false, outcome: nil))
        #expect(!LocalSummariesPromoEligibility.isEligible(isFeatureOn: true, availability: .available, isOptedIn: true, outcome: nil))
        #expect(!LocalSummariesPromoEligibility.isEligible(isFeatureOn: true, availability: .available, isOptedIn: false, outcome: .tried))
        #expect(!LocalSummariesPromoEligibility.isEligible(isFeatureOn: true, availability: .available, isOptedIn: false, outcome: .closed))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An eligible user sees the New badge, the offer and Try", .timeLimit(.minutes(1)))
    func presentationWhenEligible() {
        let presentation = promo.presentation()

        #expect(presentation?.message == UserText.newBadge)
        #expect(presentation?.secondaryText == " • " + UserText.localSummariesPromoMessage)
        #expect(presentation?.ctaLabel == UserText.localSummariesPromoTry)
        #expect(presentation?.dismissible == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Try opts in and hides the promo for good", .timeLimit(.minutes(1)))
    func tryOptsIn() {
        promo.tryNow()

        #expect(storage.pageSummariesModel == .appleIntelligence)
        #expect(promo.outcome == .tried)
        #expect(promo.presentation() == nil)

        service.optOut()
        #expect(promo.presentation() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing hides the promo for good without opting in", .timeLimit(.minutes(1)))
    func closeHidesWithoutOptIn() {
        promo.dismiss()

        #expect(storage.pageSummariesModel == .duckAI)
        #expect(promo.outcome == .closed)
        #expect(promo.presentation() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The debug reset brings the promo back", .timeLimit(.minutes(1)))
    func resetBringsItBack() {
        promo.dismiss()

        LocalSummariesPromo.resetOutcome(in: keyValueStore, notificationCenter: notificationCenter)

        #expect(promo.outcome == nil)
        #expect(promo.presentation() != nil)
    }
}
