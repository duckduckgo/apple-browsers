//
//  SubscriptionOnboardingFlowViewModelTests.swift
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingFlowViewModelTests: XCTestCase {

    // MARK: - Sequence, post-checkout

    func testWhenEntryIsPostCheckoutThenSequenceIsTheFullFlowEndingInPIR() {
        let sut = makeSUT(entryPoint: .postCheckout)

        XCTAssertEqual(sut.sequence,
                       [.orderConfirmation, .welcome, .vpnActivation, .vpnWidget, .idtr, .duckAI, .progress, .pir])
    }

    func testWhenEntryIsPostCheckoutThenCompletedSectionsAreStillWalked() {
        // Post-checkout doesn't filter; purchase moment is when entry happens.
        let sut = makeSUT(entryPoint: .postCheckout, completed: [.vpn, .widget, .idtr, .duckAI])

        XCTAssertEqual(sut.sequence,
                       [.orderConfirmation, .welcome, .vpnActivation, .vpnWidget, .idtr, .duckAI, .progress, .pir])
    }

    // MARK: - Sequence, subscription settings

    func testWhenEntryIsSettingsThenSequenceOpensAndClosesOnTheSummary() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn])

        XCTAssertEqual(sut.sequence, [.progress, .vpnWidget, .idtr, .duckAI, .progress, .pir])
    }

    func testWhenEntryIsSettingsAndNothingIsOutstandingThenSequenceIsSummaryThenPIR() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn, .widget, .idtr, .duckAI])

        XCTAssertEqual(sut.sequence, [.progress, .pir])
    }

    func testWhenEverythingIsCompleteThenSequenceIsTheSummaryAlone() {
        let sut = makeSUT(entryPoint: .subscriptionSettings,
                          completed: Set(SubscriptionOnboardingChecklistItem.allCases))

        XCTAssertEqual(sut.sequence, [.progress])
    }

    // MARK: - PIR availability

    func testWhenPIRIsUnavailableThenItIsNeverSequenced() {
        let postCheckout = makeSUT(entryPoint: .postCheckout, isPIRAvailable: false)
        let settings = makeSUT(entryPoint: .subscriptionSettings,
                               completed: [.vpn, .widget, .idtr, .duckAI],
                               isPIRAvailable: false)

        XCTAssertFalse(postCheckout.sequence.contains(.pir))
        XCTAssertEqual(settings.sequence, [.progress])
    }

    func testWhenPIRIsUnavailableThenTheChecklistDropsItAndTheCeilingIsOneHundred() {
        let sut = makeSUT(entryPoint: .postCheckout,
                          completed: [.vpn, .widget, .idtr, .duckAI],
                          isPIRAvailable: false)

        XCTAssertEqual(sut.checklist, [.vpn, .widget, .idtr, .duckAI])
        XCTAssertEqual(sut.completionPercentage, 100)
        XCTAssertEqual(sut.progressVariant, .completion)
    }

    func testWhenPIRIsAvailableThenTheInFlowCeilingIsEighty() {
        let sut = makeSUT(entryPoint: .postCheckout, completed: [.vpn, .widget, .idtr, .duckAI])

        XCTAssertEqual(sut.completionPercentage, 80)
        XCTAssertEqual(sut.progressVariant, .summary)
    }

    // MARK: - Routing

    func testWhenSectionIsRequestedPastTheEndThenItIsNil() {
        let sut = makeSUT(entryPoint: .subscriptionSettings,
                          completed: Set(SubscriptionOnboardingChecklistItem.allCases))

        XCTAssertEqual(sut.section(at: 0), .progress)
        XCTAssertNil(sut.section(at: 1))
        XCTAssertNil(sut.section(at: -1))
    }

    func testWhenTheSameSectionAppearsTwiceThenEachPositionHasItsOwnSuccessor() {
        // The two summaries in a settings-entry run are the reason routing is keyed on index, not on case.
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn, .widget, .idtr])

        XCTAssertEqual(sut.sequence, [.progress, .duckAI, .progress, .pir])
        XCTAssertEqual(sut.section(at: 1), .duckAI)
        XCTAssertEqual(sut.section(at: 3), .pir)
    }

    func testWhenProceedingThenTheCursorAdvances() {
        let sut = makeSUT(entryPoint: .postCheckout)

        sut.proceed()

        XCTAssertEqual(sut.cursor, 1)
    }

    func testWhenProceedingPastTheLastSectionThenTheFlowFinishesInsteadOfAdvancing() {
        var didFinish = false
        let sut = makeSUT(entryPoint: .subscriptionSettings,
                          completed: Set(SubscriptionOnboardingChecklistItem.allCases),
                          onFinish: { didFinish = true })

        sut.proceed()

        XCTAssertTrue(didFinish)
        XCTAssertEqual(sut.cursor, 0)
    }

    func testWhenPIRCompletesViaTheDetourThenTheSummaryFinishesInsteadOfPushingIt() {
        // Entered at 80%, so `.pir` was appended. Completing it through the detour makes that step stale.
        var didFinish = false
        let store = MockProgressStore()
        let sut = makeSUT(entryPoint: .subscriptionSettings,
                          completed: [.vpn, .widget, .idtr, .duckAI],
                          store: store,
                          onFinish: { didFinish = true })
        XCTAssertEqual(sut.sequence, [.progress, .pir])

        sut.markComplete(.pir)
        sut.proceed()

        XCTAssertTrue(didFinish)
        XCTAssertEqual(sut.cursor, 0)
    }

    func testWhenCompletionChangesMidFlowThenTheSequenceDoesNotChange() {
        // The navigation link chain is built from `sequence`; re-shaping an active link corrupts the stack.
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn])
        let original = sut.sequence

        sut.markComplete(.idtr)
        sut.markComplete(.duckAI)

        XCTAssertEqual(sut.sequence, original)
    }

    // MARK: - Navigation binding

    func testWhenCursorIsPastAnIndexThenItsBindingIsActive() {
        let sut = makeSUT(entryPoint: .postCheckout)
        let binding = sut.isPastSection(at: 0)

        XCTAssertFalse(binding.wrappedValue)
        sut.proceed()
        XCTAssertTrue(binding.wrappedValue)
    }

    func testWhenTheTopLinkIsDeactivatedThenTheCursorWalksBackOneStep() {
        let sut = makeSUT(entryPoint: .postCheckout)
        sut.proceed()
        sut.proceed()

        sut.isPastSection(at: 1).wrappedValue = false

        XCTAssertEqual(sut.cursor, 1)
    }

    func testWhenAShallowerLinkIsDeactivatedThenTheCursorIsUnchanged() {
        // Rebuilding the chain writes `false` into every link below the top one. Honouring those unwinds the
        // stack — the bug where completing the VPN step popped back to the summary.
        let sut = makeSUT(entryPoint: .postCheckout)
        sut.proceed()
        sut.proceed()

        sut.isPastSection(at: 0).wrappedValue = false

        XCTAssertEqual(sut.cursor, 2)
    }

    func testWhenAStepCompletesThenNavigationIsUntouched() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [])
        sut.proceed()

        sut.sectionDidComplete(.vpnActivation)

        XCTAssertEqual(sut.cursor, 1)
    }

    func testWhenABindingForALaterIndexIsDeactivatedThenTheCursorIsUnchanged() {
        let sut = makeSUT(entryPoint: .postCheckout)

        sut.isPastSection(at: 3).wrappedValue = false

        XCTAssertEqual(sut.cursor, 0)
    }

    // MARK: - Navigation chrome

    func testWhenSectionIsTheRootThenItShowsCloseOtherwiseBack() {
        let sut = makeSUT(entryPoint: .postCheckout)

        guard case .close = sut.navigationButton(at: 0) else {
            return XCTFail("Expected the flow root to show a close button")
        }
        guard case .back = sut.navigationButton(at: 1) else {
            return XCTFail("Expected a pushed screen to show a back button")
        }
    }

    func testWhenSectionIsAnOverviewOrSummaryThenItHasNoStepIndicator() {
        let sut = makeSUT(entryPoint: .postCheckout)

        XCTAssertNil(sut.title(at: 0))
        XCTAssertNil(sut.title(at: 1))
        XCTAssertEqual(sut.title(at: 2), String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 5))
        XCTAssertEqual(sut.title(at: 3), String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 2, 5))
    }

    func testWhenPIRIsUnavailableThenTheIndicatorCountsFourStepsNotFive() {
        let sut = makeSUT(entryPoint: .postCheckout, isPIRAvailable: false)

        XCTAssertEqual(sut.title(at: 2), String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
        XCTAssertEqual(sut.title(at: 5), String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 4, 4))
    }

    // MARK: - Completion

    func testWhenASectionCompletesThenItsChecklistItemIsRecorded() {
        let store = MockProgressStore()
        let sut = makeSUT(entryPoint: .postCheckout, store: store)

        sut.sectionDidComplete(.vpnActivation)

        XCTAssertEqual(store.completedItems, [.vpn])
        XCTAssertEqual(sut.completedItems, [.vpn])
    }

    func testWhenANonActivationSectionCompletesThenNothingIsRecorded() {
        let store = MockProgressStore()
        let sut = makeSUT(entryPoint: .postCheckout, store: store)

        sut.sectionDidComplete(.welcome)
        sut.sectionDidComplete(.progress)

        XCTAssertTrue(store.completedItems.isEmpty)
    }

    func testWhenAnItemIsCompletedTwiceThenItIsRecordedOnce() {
        let sut = makeSUT(entryPoint: .postCheckout)

        sut.markComplete(.vpn)
        sut.markComplete(.vpn)

        XCTAssertEqual(sut.completedItems, [.vpn])
        XCTAssertEqual(sut.completionPercentage, 20)
    }

    func testWhenSectionRequestsAdvanceThenTheFlowProceeds() {
        let sut = makeSUT(entryPoint: .postCheckout)

        sut.sectionDidRequestAdvance()

        XCTAssertEqual(sut.cursor, 1)
    }

    func testWhenSectionRequestsDuckAIChatThenTheRequestIsForwardedWithItsModel() {
        var requestedModelID: String?
        let sut = makeSUT(entryPoint: .postCheckout, onRequestDuckAIChat: { requestedModelID = $0 })

        sut.sectionDidRequestDuckAIChat(modelID: "claude-sonnet-5")

        XCTAssertEqual(requestedModelID, "claude-sonnet-5")
    }

    // MARK: - Helpers

    private func makeSUT(entryPoint: SubscriptionOnboardingEntryPoint,
                         completed: Set<SubscriptionOnboardingChecklistItem> = [],
                         isPIRAvailable: Bool = true,
                         store: MockProgressStore? = nil,
                         onFinish: @escaping () -> Void = {},
                         onRequestDuckAIChat: @escaping (String?) -> Void = { _ in }) -> SubscriptionOnboardingFlowViewModel {
        let store = store ?? MockProgressStore()
        store.completedItems = store.completedItems.union(completed)
        return SubscriptionOnboardingFlowViewModel(entryPoint: entryPoint,
                                                   store: store,
                                                   isPIRAvailable: isPIRAvailable,
                                                   onFinish: onFinish,
                                                   onRequestDuckAIChat: onRequestDuckAIChat)
    }
}

/// A reference-typed store so a test can observe writes the flow makes through its own copy.
private final class MockProgressStore: SubscriptionOnboardingProgressStoring {
    var completedItems: Set<SubscriptionOnboardingChecklistItem> = []
    var cardFirstShownDate: Date?
}
