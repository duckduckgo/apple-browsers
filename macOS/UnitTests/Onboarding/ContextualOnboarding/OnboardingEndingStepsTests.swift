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

import FeatureFlags_macOS
@_spi(Testing) import Persistence
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct OnboardingEndingStepsTests {

    let experiment = SpyOnboardingSubscriptionUpsellEnrolling()
    let progress = ContextualOnboardingProgress(storage: MockContextualDialogStateStoring(),
                                                settings: InMemoryThrowingKeyValueStore().throwingKeyedStoring())
    let sut: OnboardingEndingSteps

    init() {
        sut = OnboardingEndingSteps(progress: progress, subscriptionUpsellExperiment: experiment)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Starting the ending enrolls once and shows High Five", .timeLimit(.minutes(1)))
    func startEnrollsAndShowsHighFive() {
        #expect(sut.start() == .next(.highFive))
        #expect(experiment.enrollCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before High Five the ending leaves the decision to the path", .timeLimit(.minutes(1)))
    func notStartedReturnsNil() {
        progress.markSeen(.tryASearch)
        progress.markSeen(.defaultTrackers)

        #expect(sut.decisionForNextDialog() == nil)
        #expect(experiment.enrollCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("After High Five, the treatment cohort gets the upsell and the others complete", .timeLimit(.minutes(1)),
          arguments: [(FeatureFlag.OnboardingSubscriptionUpsellCohort?.some(.treatment), ContextualOnboardingDecision.next(.subscriptionUpsell)),
                      (.some(.control), .completed),
                      (nil, .completed)])
    func afterHighFive(cohort: FeatureFlag.OnboardingSubscriptionUpsellCohort?, expected: ContextualOnboardingDecision) {
        experiment.cohortStub = cohort
        progress.markSeen(.highFive)

        #expect(sut.decisionForNextDialog() == expected)
        #expect(sut.gotItPressed(after: .highFive) == expected)
        #expect(experiment.enrollCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once the upsell was seen, onboarding completes", .timeLimit(.minutes(1)))
    func upsellSeenCompletes() {
        experiment.cohortStub = .treatment
        progress.markSeen(.highFive)
        progress.markSeen(.subscriptionUpsell)

        #expect(sut.decisionForNextDialog() == .completed)
        #expect(sut.gotItPressed(after: .subscriptionUpsell) == .completed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it on a dialog before the ending is left to the path", .timeLimit(.minutes(1)),
          arguments: [ContextualDialogType.tryASearch, .tryASite, .defaultTrackers, .tryFireButton, .defaultSearchDone])
    func gotItBeforeEndingReturnsNil(dialog: ContextualDialogType) {
        #expect(sut.gotItPressed(after: dialog) == nil)
    }
}
