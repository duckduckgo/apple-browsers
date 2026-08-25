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
import SwiftUI
import Subscription
import PrivacyConfig
import PixelKit
import PixelExperimentKit

@MainActor
final class SubscriptionOnboardingFlowViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PixelKit.configureExperimentKit(featureFlagger: PrivacyConfig.MockFeatureFlagger(),
                                         eventTracker: ExperimentEventTracker(),
                                         fire: { _, _, _ in })
    }

    // MARK: - Sequence, post-checkout

    func testWhenEntryIsPostCheckoutThenSequenceIsTheFullFlowEndingInTheSummary() {
        let sut = makeSUT(entryPoint: .postCheckout)

        XCTAssertEqual(sut.sequence,
                       [.orderConfirmation, .welcome, .vpnActivation, .vpnWidget, .vpnTips, .idtr, .duckAI, .progress])
    }

    func testWhenEntryIsPostCheckoutThenAlreadyCompletedSectionsAreSkipped() {
        let sut = makeSUT(entryPoint: .postCheckout, completed: [.duckAI])

        XCTAssertEqual(sut.sequence, [.orderConfirmation, .welcome, .vpnActivation, .vpnWidget, .vpnTips, .idtr, .progress])
    }

    func testWhenEntryIsPostCheckoutAndEverythingIsAlreadyCompleteThenOnlyTheOverviewAndSummaryShow() {
        let sut = makeSUT(entryPoint: .postCheckout, completed: [.vpn, .vpnWidget, .idtr, .duckAI])

        XCTAssertEqual(sut.sequence, [.orderConfirmation, .welcome, .progress])
    }

    // MARK: - Sequence, subscription settings

    func testWhenEntryIsSettingsThenSequenceResumesAtTheFirstUnfinishedSectionAndClosesOnTheSummary() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn])

        XCTAssertEqual(sut.sequence, [.vpnWidget, .vpnTips, .idtr, .duckAI, .progress])
    }

    func testWhenEverythingIsCompleteThenSequenceIsTheSummaryAlone() {
        let sut = makeSUT(entryPoint: .subscriptionSettings,
                          completed: Set(SubscriptionOnboardingChecklistItem.allCases))

        XCTAssertEqual(sut.sequence, [.progress])
    }

    func testWhenNothingIsOutstandingThenSequenceIsTheSummaryAlone() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn, .vpnWidget, .idtr, .duckAI])

        XCTAssertEqual(sut.sequence, [.progress])
    }

    /// `.vpnTips` never appears alone: it is bundled with `.vpnWidget` in both directions — present together
    /// when entitled and incomplete, absent together once `.vpnWidget` is done (or ungated — see the
    /// entitlement-gating tests below).
    func testWhenVpnWidgetIsOutstandingThenVpnTipsIsPresentRightAfterIt() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn])

        XCTAssertEqual(sut.sequence.firstIndex(of: .vpnTips), sut.sequence.firstIndex(of: .vpnWidget).map { $0 + 1 })
    }

    func testWhenVpnWidgetIsCompleteThenVpnTipsIsAlsoAbsent() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn, .vpnWidget])

        XCTAssertFalse(sut.sequence.contains(.vpnWidget))
        XCTAssertFalse(sut.sequence.contains(.vpnTips))
    }

    // MARK: - Sequence invariants

    func testWhenSequenceIsBuiltThenNoSectionRepeats() {
        // Routing resolves a section's successor by looking it up in `sequence`, so a repeat would resolve to
        // the wrong position — the closing summary would push the section after the opening one, forever.
        let suts = [makeSUT(entryPoint: .postCheckout),
                    makeSUT(entryPoint: .subscriptionSettings, completed: []),
                    makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn, .vpnWidget, .idtr]),
                    makeSUT(entryPoint: .subscriptionSettings,
                            completed: Set(SubscriptionOnboardingChecklistItem.allCases))]

        for sut in suts {
            XCTAssertEqual(sut.sequence.count, Set(sut.sequence).count, "Repeated section in \(sut.sequence)")
        }
    }

    func testWhenSequenceIsBuiltThenPIRIsNeverASection() {
        XCTAssertFalse(makeSUT(entryPoint: .postCheckout).sequence.contains(.pir))
        XCTAssertFalse(makeSUT(entryPoint: .subscriptionSettings, completed: []).sequence.contains(.pir))
    }

    // MARK: - PIR availability

    // Percentages are `SubscriptionOnboardingProgress`'s job and covered by its own tests; the flow only
    // has to hand screens the right checklist.

    func testWhenPIRIsUnavailableThenTheChecklistDropsIt() {
        let sut = makeSUT(entryPoint: .postCheckout, isPIRAvailable: false)

        XCTAssertEqual(sut.progress.checklist, [.vpn, .vpnWidget, .idtr, .duckAI])
    }

    func testWhenPIRIsAvailableThenTheChecklistHasAllFiveItems() {
        let sut = makeSUT(entryPoint: .postCheckout)

        XCTAssertEqual(sut.progress.checklist, [.vpn, .vpnWidget, .idtr, .duckAI, .pir])
    }

    /// `.vpnTips` is a real checklist item (so its section can carry a `.kind`), but it's excluded from the
    /// checklist itself regardless of PIR availability — it piggybacks on `.vpnWidget` instead of counting.
    func testVpnTipsIsExcludedFromTheChecklistRegardlessOfPIRAvailability() {
        XCTAssertFalse(makeSUT(entryPoint: .postCheckout, isPIRAvailable: true).progress.checklist.contains(.vpnTips))
        XCTAssertFalse(makeSUT(entryPoint: .postCheckout, isPIRAvailable: false).progress.checklist.contains(.vpnTips))
    }

    // MARK: - Entitlement gating

    func testWhenEntitlementExcludesDuckAIThenItsSectionIsDroppedFromTheSequence() {
        let entitlement = EntitlementStatus(networkProtection: true, dataBrokerProtection: true,
                                            identityTheftRestoration: true, identityTheftRestorationGlobal: true,
                                            paidAIChat: false)
        let sut = makeSUT(entryPoint: .postCheckout, entitlement: entitlement)

        XCTAssertEqual(sut.sequence, [.orderConfirmation, .welcome, .vpnActivation, .vpnWidget, .vpnTips, .idtr, .progress])
    }

    func testWhenEntitlementExcludesVPNThenVPNAndItsWidgetAreDroppedFromTheSequence() {
        let entitlement = EntitlementStatus(networkProtection: false, dataBrokerProtection: true,
                                            identityTheftRestoration: true, identityTheftRestorationGlobal: true,
                                            paidAIChat: true)
        let sut = makeSUT(entryPoint: .postCheckout, entitlement: entitlement)

        // .vpnTips shares .vpnWidget's networkProtection gate, so it drops right along with it.
        XCTAssertFalse(sut.sequence.contains(.vpnTips))
        XCTAssertEqual(sut.sequence, [.orderConfirmation, .welcome, .idtr, .duckAI, .progress])
    }

    /// Entitlement gating composes with the existing completed-items filter on resume.
    func testWhenEntitlementExcludesAnItemThenSettingsResumeSkipsItToo() {
        let entitlement = EntitlementStatus(networkProtection: true, dataBrokerProtection: true,
                                            identityTheftRestoration: true, identityTheftRestorationGlobal: true,
                                            paidAIChat: false)
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn], entitlement: entitlement)

        XCTAssertEqual(sut.sequence, [.vpnWidget, .vpnTips, .idtr, .progress])
    }

    /// No fallback: an empty checklist just means no activation sections appear. The launcher (not the VM)
    /// is responsible for refusing to present a flow whose checklist came back empty — see
    /// `SubscriptionOnboardingLauncherTests`.
    func testWhenNothingIsEntitledThenNoActivationSectionsAppear() {
        let sut = makeSUT(entryPoint: .postCheckout, entitlement: .empty)

        XCTAssertEqual(sut.sequence, [.orderConfirmation, .welcome, .progress])
    }

    // MARK: - Routing

    func testWhenASectionIsTheLastThenItHasNoSuccessor() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn, .vpnWidget, .idtr])

        XCTAssertEqual(sut.sequence, [.duckAI, .progress])
        XCTAssertEqual(sut.section(after: .duckAI), .progress)
        XCTAssertNil(sut.section(after: .progress))
    }

    func testWhenASectionIsNotInTheSequenceThenItHasNoSuccessor() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn, .vpnWidget, .idtr])

        XCTAssertNil(sut.section(after: .orderConfirmation))
    }

    func testWhenProceedingThenTheFlowMovesToTheNextSection() {
        let sut = makeSUT(entryPoint: .postCheckout)

        sut.proceed()

        XCTAssertEqual(sut.currentSection, .welcome)
    }

    func testWhenProceedingPastTheLastSectionThenTheFlowFinishesInsteadOfAdvancing() {
        var didFinish = false
        let sut = makeSUT(entryPoint: .subscriptionSettings,
                          completed: Set(SubscriptionOnboardingChecklistItem.allCases),
                          onFinish: { didFinish = true })

        sut.proceed()

        XCTAssertTrue(didFinish)
        XCTAssertEqual(sut.currentSection, .progress)
    }

    func testWhenCompletionChangesMidFlowThenTheSequenceDoesNotChange() {
        // The navigation link chain is built from `sequence`; re-shaping an active link corrupts the stack.
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [.vpn])
        let original = sut.sequence

        sut.progress.markComplete(.idtr)
        sut.progress.markComplete(.duckAI)

        XCTAssertEqual(sut.sequence, original)
    }

    // MARK: - Navigation binding

    func testWhenTheFlowIsPastASectionThenItsBindingIsActive() {
        let sut = makeSUT(entryPoint: .postCheckout)
        let binding = sut.isPastSection(.orderConfirmation)

        XCTAssertFalse(binding.wrappedValue)
        sut.proceed()
        XCTAssertTrue(binding.wrappedValue)
    }

    func testWhenTheTopLinkIsDeactivatedThenTheFlowWalksBackOneSection() {
        let sut = makeSUT(entryPoint: .postCheckout)
        sut.proceed()
        sut.proceed()

        sut.isPastSection(.welcome).wrappedValue = false

        XCTAssertEqual(sut.currentSection, .welcome)
    }

    func testWhenAShallowerLinkIsDeactivatedThenTheFlowIsUnchanged() {
        // Rebuilding the chain writes `false` into every link below the top one. Honouring those unwinds the
        // stack — the bug where completing the VPN step popped back to the summary.
        let sut = makeSUT(entryPoint: .postCheckout)
        sut.proceed()
        sut.proceed()

        sut.isPastSection(.orderConfirmation).wrappedValue = false

        XCTAssertEqual(sut.currentSection, .vpnActivation)
    }

    func testWhenAStepCompletesThenNavigationIsUntouched() {
        let sut = makeSUT(entryPoint: .subscriptionSettings, completed: [])
        sut.proceed()

        sut.sectionDidComplete(.vpnActivation)

        XCTAssertEqual(sut.currentSection, .vpnWidget)
    }

    func testWhenABindingForALaterSectionIsDeactivatedThenTheFlowIsUnchanged() {
        let sut = makeSUT(entryPoint: .postCheckout)

        sut.isPastSection(.vpnWidget).wrappedValue = false

        XCTAssertEqual(sut.currentSection, .orderConfirmation)
    }

    // MARK: - Navigation chrome

    func testWhenSectionIsTheRootThenItShowsCloseOtherwiseBack() {
        let sut = makeSUT(entryPoint: .postCheckout)

        guard case .close = sut.navigationButton(for: .orderConfirmation) else {
            return XCTFail("Expected the flow root to show a close button")
        }
        guard case .back = sut.navigationButton(for: .welcome) else {
            return XCTFail("Expected a pushed screen to show a back button")
        }
    }

    func testWhenSectionIsAnOverviewOrSummaryThenItHasNoStepIndicator() {
        let sut = makeSUT(entryPoint: .postCheckout)

        XCTAssertNil(sut.title(for: .orderConfirmation))
        XCTAssertNil(sut.title(for: .welcome))
        XCTAssertNil(sut.title(for: .progress))
        XCTAssertEqual(sut.title(for: .vpnActivation),
                       String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 5))
        XCTAssertEqual(sut.title(for: .vpnWidget),
                       String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 2, 5))
        // .vpnTips piggybacks on .vpnWidget's step number rather than being independently numbered.
        XCTAssertEqual(sut.title(for: .vpnTips), sut.title(for: .vpnWidget))
    }

    func testWhenPIRIsUnavailableThenTheIndicatorCountsFourStepsNotFive() {
        let sut = makeSUT(entryPoint: .postCheckout, isPIRAvailable: false)

        XCTAssertEqual(sut.title(for: .vpnActivation),
                       String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 1, 4))
        XCTAssertEqual(sut.title(for: .duckAI),
                       String(format: UserText.subscriptionOnboardingStepIndicatorFormat, 4, 4))
    }

    // MARK: - Completion

    func testWhenASectionCompletesThenItsChecklistItemIsRecorded() {
        let store = MockProgressStore()
        let sut = makeSUT(entryPoint: .postCheckout, store: store)

        sut.sectionDidComplete(.vpnActivation)

        XCTAssertEqual(store.completedItems, [.vpn])
        XCTAssertEqual(sut.progress.completedItems, [.vpn])
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

        sut.progress.markComplete(.vpn)
        sut.progress.markComplete(.vpn)

        XCTAssertEqual(sut.progress.completedItems, [.vpn])
    }

    func testWhenSectionRequestsAdvanceThenTheFlowProceeds() {
        let sut = makeSUT(entryPoint: .postCheckout)

        sut.sectionDidRequestAdvance()

        XCTAssertEqual(sut.currentSection, .welcome)
    }

    func testWhenSectionRequestsDuckAIChatThenTheRequestIsForwardedWithItsModel() {
        var requestedModelID: String?
        let sut = makeSUT(entryPoint: .postCheckout, onRequestDuckAIChat: {
            requestedModelID = $0
            return true
        })

        let launched = sut.sectionDidRequestDuckAIChat(modelID: "claude-sonnet-5")

        XCTAssertEqual(requestedModelID, "claude-sonnet-5")
        XCTAssertTrue(launched)
    }

    func testWhenTheDuckAIChatDoesNotLaunchThenTheFailureIsForwardedBack() {
        let sut = makeSUT(entryPoint: .postCheckout, onRequestDuckAIChat: { _ in false })

        XCTAssertFalse(sut.sectionDidRequestDuckAIChat(modelID: "claude-sonnet-5"))
    }

    // MARK: - Funnel reporting

    func testWhenASectionCompletesThenItIsReportedCompleted() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)

        sut.sectionDidComplete(.vpnActivation)

        XCTAssertEqual(spy.completed, [.vpnActivation])
        XCTAssertTrue(spy.skipped.isEmpty)
    }

    /// Re-entering an already-completed activation section (e.g. via a navigation quirk) must not re-fire the
    /// completion pixel.
    func testWhenAnAlreadyCompletedSectionCompletesAgainThenItIsNotReportedTwice() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)

        sut.sectionDidComplete(.vpnActivation)
        sut.sectionDidComplete(.vpnActivation)

        XCTAssertEqual(spy.completed, [.vpnActivation])
    }

    /// `.vpnTips` is bundled with `.vpnWidget`: completing `.vpnWidget` is what counts as the bundle completing,
    /// and `.vpnTips` must never fire a completion pixel of its own — it would just duplicate `.vpnWidget`'s.
    func testWhenVpnTipsCompletesThenNoCompletionIsReported() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)

        sut.sectionDidComplete(.vpnTips)

        XCTAssertTrue(spy.completed.isEmpty)
    }

    /// `.vpnWidget`'s own completion is the bundle's one and only completion signal.
    func testWhenVpnWidgetCompletesThenItAloneIsReportedCompleted() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)

        sut.sectionDidComplete(.vpnWidget)
        sut.sectionDidComplete(.vpnTips)

        XCTAssertEqual(spy.completed, [.vpnWidget])
    }

    /// The VPN's on-state "Next" and its permission-denied "Skip" share `advance()`, so the skip is derived
    /// from the item still being incomplete.
    func testWhenLeavingTheVPNStepWithoutTurningItOnThenItIsReportedSkipped() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)
        sut.proceed()
        sut.proceed()
        XCTAssertEqual(sut.currentSection, .vpnActivation)

        sut.sectionDidRequestAdvance()

        XCTAssertEqual(spy.skipped, [.vpnActivation])
    }

    func testWhenLeavingTheVPNStepAfterTurningItOnThenNoSkipIsReported() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)
        sut.proceed()
        sut.proceed()
        sut.sectionDidComplete(.vpnActivation)

        sut.sectionDidRequestAdvance()

        XCTAssertTrue(spy.skipped.isEmpty)
    }

    /// Advancing from Duck.ai is itself the skip: starting a chat shows the interstitial instead of advancing.
    func testWhenLeavingDuckAIThenItIsReportedSkipped() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .subscriptionSettings,
                          completed: [.vpn, .vpnWidget, .idtr],
                          instrumentation: spy)
        XCTAssertEqual(sut.currentSection, .duckAI)

        sut.sectionDidRequestAdvance()

        XCTAssertEqual(spy.skipped, [.duckAI])
    }

    func testWhenLeavingAStepWithNoSkipCTAThenNoSkipIsReported() {
        for section in [SubscriptionOnboardingSection.orderConfirmation, .welcome, .vpnWidget, .vpnTips, .idtr] {
            let spy = SpyInstrumentation()
            let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)
            while sut.currentSection != section, sut.currentSection != nil {
                sut.proceed()
            }
            // Activation steps mark themselves complete before advancing; overviews have no item at all.
            if case .activation = section.kind {
                sut.sectionDidComplete(section)
            }

            sut.sectionDidRequestAdvance()

            XCTAssertTrue(spy.skipped.isEmpty, "\(section) should have no skip CTA to report")
        }
    }

    // MARK: - Funnel reporting, PIR sheet

    func testWhenThePIRSheetOpensThenItIsReportedShown() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)

        sut.reportPIRPresentation(true)

        XCTAssertEqual(spy.shown, [.pir])
        XCTAssertTrue(spy.completed.isEmpty)
    }

    func testWhenThePIRSheetClosesAfterAProfileIsSavedThenItIsReportedCompleted() {
        let spy = SpyInstrumentation()
        let store = MockProgressStore()
        let sut = makeSUT(entryPoint: .postCheckout, store: store, instrumentation: spy)
        sut.reportPIRPresentation(true)

        // What saving a Data Broker Protection profile writes, from outside the flow.
        store.completedItems.insert(.pir)
        sut.reportPIRPresentation(false)

        XCTAssertEqual(spy.shown, [.pir])
        XCTAssertEqual(spy.completed, [.pir])
    }

    /// Closing the sheet is not a skip — PIR has a close button, not a skip CTA.
    func testWhenThePIRSheetClosesWithoutAProfileThenNothingFurtherIsReported() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)
        sut.reportPIRPresentation(true)

        sut.reportPIRPresentation(false)

        XCTAssertEqual(spy.shown, [.pir])
        XCTAssertTrue(spy.completed.isEmpty)
        XCTAssertTrue(spy.skipped.isEmpty)
    }

    // MARK: - Funnel reporting, shown

    /// `shown` must come from the screen appearing, never from the factory building it — on iOS 15 a
    /// `NavigationLink` builds its destination before pushing it.
    func testWhenAScreenIsBuiltThenItIsNotYetReportedShown() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)
        let factory = SubscriptionOnboardingViewFactory(flow: sut)

        _ = factory.screen(for: .welcome)

        XCTAssertTrue(spy.shown.isEmpty)
    }

    /// `.vpnTips` shares `.vpnWidget`'s pixel name, so its own appearance must not fire a second
    /// "vpn_widget shown" — only `.vpnWidget`'s own appearance should count.
    func testWhenVpnTipsAppearsThenNoShownIsReported() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)
        let factory = SubscriptionOnboardingViewFactory(flow: sut)

        factory.reportShown(.vpnTips)

        XCTAssertTrue(spy.shown.isEmpty)
    }

    func testWhenVpnWidgetAppearsThenItIsReportedShown() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(entryPoint: .postCheckout, instrumentation: spy)
        let factory = SubscriptionOnboardingViewFactory(flow: sut)

        factory.reportShown(.vpnWidget)

        XCTAssertEqual(spy.shown, [.vpnWidget])
    }

    // MARK: - Helpers

    private func makeSUT(entryPoint: SubscriptionOnboardingEntryPoint,
                         completed: Set<SubscriptionOnboardingChecklistItem> = [],
                         isPIRAvailable: Bool = true,
                         entitlement: EntitlementStatus = .allEnabled,
                         store: MockProgressStore? = nil,
                         instrumentation: SubscriptionOnboardingInstrumenting? = nil,
                         onFinish: @escaping () -> Void = {},
                         onRequestDuckAIChat: @escaping (String?) -> Bool = { _ in true }) -> SubscriptionOnboardingFlowViewModel {
        let store = store ?? MockProgressStore()
        store.completedItems = store.completedItems.union(completed)
        let progress = SubscriptionOnboardingProgress(persistor: store, isPIRAvailable: isPIRAvailable, entitlement: entitlement)
        return SubscriptionOnboardingFlowViewModel(entryPoint: entryPoint,
                                                  progress: progress,
                                                  onFinish: onFinish,
                                                  onRequestDuckAIChat: onRequestDuckAIChat,
                                                  instrumentation: instrumentation ?? NullSubscriptionOnboardingInstrumentation(),
                                                  pirScreen: { EmptyView() })
    }
}

/// Records what the flow reported, so a test can assert the funnel rather than only the pixel names.
private final class SpyInstrumentation: SubscriptionOnboardingInstrumenting {
    private(set) var shown: [SubscriptionOnboardingSection] = []
    private(set) var completed: [SubscriptionOnboardingSection] = []
    private(set) var skipped: [SubscriptionOnboardingSection] = []

    /// Deliberately unrecorded: asserting it would mean calling `startPrefetching()`, which starts real
    /// fetches. The flow-start pixel is covered by `SubscriptionOnboardingInstrumentationTests`.
    func flowStarted() {}
    func stepShown(_ section: SubscriptionOnboardingSection) { shown.append(section) }
    func stepCompleted(_ section: SubscriptionOnboardingSection) { completed.append(section) }
    func stepSkipped(_ section: SubscriptionOnboardingSection) { skipped.append(section) }
}

/// A reference-typed persistor so a test can observe writes the flow makes through its own copy.
private final class MockProgressStore: SubscriptionOnboardingProgressPersisting {
    var completedItems: Set<SubscriptionOnboardingChecklistItem> = []
    var cardFirstShownDate: Date?
    var fullyCompletedAt: Date?
    var postCheckoutFlowStartedAt: Date?
}
