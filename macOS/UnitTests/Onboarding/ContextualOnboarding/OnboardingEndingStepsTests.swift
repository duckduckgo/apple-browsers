//
//  OnboardingEndingStepsTests.swift
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

@_spi(Testing) import Persistence
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct OnboardingEndingStepsTests {

    let eligibility = StubOnboardingSubscriptionUpsellEligibility()
    let storage = MockOnboardingEndingStoring()
    let progress = ContextualOnboardingProgress(storage: MockContextualDialogStateStoring(),
                                                settings: InMemoryThrowingKeyValueStore().throwingKeyedStoring())
    let sut: OnboardingEndingSteps

    init() {
        sut = OnboardingEndingSteps(progress: progress, storage: storage, subscriptionUpsellEligibility: eligibility)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Starting the ending shows High Five", .timeLimit(.minutes(1)))
    func startShowsHighFive() {
        #expect(sut.start() == .next(.highFive))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before High Five the ending leaves the decision to the path", .timeLimit(.minutes(1)))
    func notStartedBeforeHighFive() {
        progress.markSeen(.tryASearch)
        progress.markSeen(.defaultTrackers)

        #expect(sut.decisionForNextDialog() == .notStarted)
    }

    @available(iOS 16, macOS 13, *)
    @Test("After High Five, eligible users get the upsell and the others complete", .timeLimit(.minutes(1)),
          arguments: [(true, ContextualOnboardingDecision.next(.subscriptionUpsell)),
                      (false, .completed)])
    func afterHighFive(isEligible: Bool, expected: ContextualOnboardingDecision) {
        eligibility.isUserEligible = isEligible
        progress.markSeen(.highFive)

        #expect(sut.decisionForNextDialog() == .decided(expected))
        #expect(sut.gotItPressed(after: .highFive) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once the upsell was seen, onboarding completes", .timeLimit(.minutes(1)))
    func upsellSeenCompletes() {
        eligibility.isUserEligible = true
        progress.markSeen(.highFive)
        progress.markSeen(.subscriptionUpsell)

        #expect(sut.decisionForNextDialog() == .decided(.completed))
        #expect(sut.gotItPressed(after: .subscriptionUpsell) == .completed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it on a dialog that isn't part of the ending shows nothing", .timeLimit(.minutes(1)),
          arguments: [ContextualDialogType.tryASearch, .tryASite, .defaultTrackers, .tryFireButton, .defaultSearchDone])
    func gotItOutsideEndingShowsNothing(dialog: ContextualDialogType) {
        #expect(sut.gotItPressed(after: dialog) == .none)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Starting the ending saves the user's eligibility", .timeLimit(.minutes(1)),
          arguments: [Bool?.some(true), .some(false), nil])
    func startSavesEligibility(isUserEligible: Bool?) {
        eligibility.isUserEligible = isUserEligible

        _ = sut.start()

        #expect(storage.subscriptionUpsellEligible == isUserEligible)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Starting the ending again keeps the first saved answer", .timeLimit(.minutes(1)))
    func startKeepsSavedEligibility() {
        storage.subscriptionUpsellEligible = true
        eligibility.isUserEligible = false

        _ = sut.start()

        #expect(storage.subscriptionUpsellEligible == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("After High Five, the saved eligibility wins over the current one", .timeLimit(.minutes(1)),
          arguments: [(true, Bool?.some(false), ContextualOnboardingDecision.next(.subscriptionUpsell)),
                      (true, nil, .next(.subscriptionUpsell)),
                      (false, .some(true), .completed)])
    func savedEligibilityWins(saved: Bool, current: Bool?, expected: ContextualOnboardingDecision) {
        storage.subscriptionUpsellEligible = saved
        eligibility.isUserEligible = current
        progress.markSeen(.highFive)

        #expect(sut.decisionForNextDialog() == .decided(expected))
        #expect(sut.gotItPressed(after: .highFive) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With nothing saved and eligibility still unknown, High Five completes onboarding", .timeLimit(.minutes(1)))
    func unknownEligibilityCompletes() {
        eligibility.isUserEligible = nil
        progress.markSeen(.highFive)

        #expect(sut.gotItPressed(after: .highFive) == .completed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Turning the upsell off remotely completes onboarding at High Five, even mid-onboarding", .timeLimit(.minutes(1)))
    func killSwitchCompletes() {
        eligibility.isUserEligible = true
        _ = sut.start()
        progress.markSeen(.highFive)
        #expect(sut.decisionForNextDialog() == .decided(.next(.subscriptionUpsell)))

        eligibility.isUpsellEnabled = false

        #expect(sut.decisionForNextDialog() == .decided(.completed))
        #expect(sut.gotItPressed(after: .highFive) == .completed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reset clears the saved eligibility", .timeLimit(.minutes(1)))
    func resetClearsSavedEligibility() {
        storage.subscriptionUpsellEligible = true

        sut.reset()

        #expect(storage.subscriptionUpsellEligible == nil)
    }
}
