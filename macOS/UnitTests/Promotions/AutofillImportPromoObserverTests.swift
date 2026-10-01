//
//  AutofillImportPromoObserverTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

private enum Action {
    case startImport
    case permanentlyDismiss
}

private extension AutofillImportPromoObserver {
    @MainActor
    func perform(_ action: Action, from overlay: AnyObject) {
        switch action {
        case .startImport: overlayDidStartImport(overlay)
        case .permanentlyDismiss: overlayDidPermanentlyDismissImportPrompt(overlay)
        }
    }
}

@MainActor
final class AutofillImportPromoObserverTests: XCTestCase {

    private var sut: AutofillImportPromoObserver!
    private var cancellables: Set<AnyCancellable>!
    private var received: [Bool]!

    // Stand-ins for overlay view controllers; only their identity matters.
    private var overlayA: NSObject!
    private var overlayB: NSObject!

    override func setUp() {
        super.setUp()
        sut = AutofillImportPromoObserver()
        cancellables = []
        received = []
        overlayA = NSObject()
        overlayB = NSObject()
    }

    override func tearDown() {
        cancellables = nil
        received = nil
        sut = nil
        overlayA = nil
        overlayB = nil
        super.tearDown()
    }

    private func recordEmissions() {
        sut.isVisiblePublisher
            .sink { [weak self] in self?.received.append($0) }
            .store(in: &cancellables)
    }

    // MARK: - Visibility

    func testWhenCreatedThenNotVisibleAndCurrentValueIsReplayed() {
        recordEmissions()

        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(received, [false])
        XCTAssertEqual(sut.resultWhenHidden, .ignored(cooldown: 0))
    }

    func testWhenSubscribingWhileVisibleThenTrueIsReplayed() {
        sut.overlayDidShowImportPrompt(overlayA)

        recordEmissions()

        XCTAssertEqual(received, [true])
    }

    func testWhenOverlayShowsThenHidesThenVisibilityFollows() {
        recordEmissions()

        sut.overlayDidShowImportPrompt(overlayA)
        XCTAssertTrue(sut.isVisible)

        sut.overlayDidHideImportPrompt(overlayA)
        XCTAssertFalse(sut.isVisible)

        XCTAssertEqual(received, [false, true, false])
    }

    func testWhenSameOverlayShowsTwiceThenOneHideHidesIt() {
        recordEmissions()

        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidHideImportPrompt(overlayA)

        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(received, [false, true, false])
    }

    func testWhenNewOverlayReplacesCurrentOneThenPreviousIsClosedFirst() {
        recordEmissions()

        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidShowImportPrompt(overlayB)
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqual(received, [false, true, false, true])
        XCTAssertEqual(sut.resultWhenHidden, .ignored(cooldown: 0))

        sut.overlayDidHideImportPrompt(overlayA)
        XCTAssertTrue(sut.isVisible, "A late hide from the replaced overlay must not hide the current one")
        XCTAssertEqual(received, [false, true, false, true])

        sut.overlayDidHideImportPrompt(overlayB)
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(received, [false, true, false, true, false])
    }

    func testWhenUnknownOrAlreadyHiddenOverlayHidesThenNothingChanges() {
        recordEmissions()

        sut.overlayDidHideImportPrompt(overlayA)
        sut.overlayDidShowImportPrompt(overlayB)
        sut.overlayDidHideImportPrompt(overlayA)
        XCTAssertTrue(sut.isVisible, "A stray hide must not hide another overlay's prompt")

        sut.overlayDidHideImportPrompt(overlayB)
        sut.overlayDidHideImportPrompt(overlayB)

        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(received, [false, true, false])
    }

    // MARK: - Result when hidden

    func testResultWhenHiddenForEachResolutionPath() {
        let cases: [(actions: [Action], expected: PromoResult)] = [
            ([], .ignored(cooldown: 0)),
            ([.startImport], .actioned),
            ([.permanentlyDismiss], .ignored())
        ]

        for (actions, expected) in cases {
            let observer = AutofillImportPromoObserver()
            observer.overlayDidShowImportPrompt(overlayA)
            actions.forEach { observer.perform($0, from: overlayA) }
            observer.overlayDidHideImportPrompt(overlayA)

            XCTAssertEqual(observer.resultWhenHidden, expected, "\(actions)")
        }
    }

    func testWhenActionComesFromUntrackedOverlayThenItIsIgnored() {
        sut.perform(.startImport, from: overlayA)
        sut.overlayDidShowImportPrompt(overlayA)
        sut.perform(.startImport, from: overlayB)
        sut.perform(.permanentlyDismiss, from: overlayB)
        sut.overlayDidHideImportPrompt(overlayA)

        XCTAssertEqual(sut.resultWhenHidden, .ignored(cooldown: 0))
    }

    func testWhenShownAgainAfterActionThenOutcomeIsNotDowngraded() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.perform(.startImport, from: overlayA)
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidHideImportPrompt(overlayA)

        XCTAssertEqual(sut.resultWhenHidden, .actioned)
    }

    func testWhenReplacedOverlayWasPermanentlyDismissedThenItsOutcomeIsResolved() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.perform(.permanentlyDismiss, from: overlayA)
        sut.overlayDidShowImportPrompt(overlayB)

        XCTAssertEqual(sut.resultWhenHidden, .ignored())
    }

    func testWhenNewStretchHasNoActionThenResultResets() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.perform(.startImport, from: overlayA)
        sut.overlayDidHideImportPrompt(overlayA)
        XCTAssertEqual(sut.resultWhenHidden, .actioned)

        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidHideImportPrompt(overlayA)

        XCTAssertEqual(sut.resultWhenHidden, .ignored(cooldown: 0))
    }

    func testWhenVisibilityBecomesFalseThenResultIsAlreadyResolved() {
        var resultWhenHiddenOnEmission: PromoResult?
        sut.overlayDidShowImportPrompt(overlayA)
        sut.isVisiblePublisher
            .filter { !$0 }
            .sink { [weak self] _ in resultWhenHiddenOnEmission = self?.sut.resultWhenHidden }
            .store(in: &cancellables)

        sut.perform(.permanentlyDismiss, from: overlayA)
        sut.overlayDidHideImportPrompt(overlayA)

        XCTAssertEqual(resultWhenHiddenOnEmission, .ignored())
    }

    // MARK: - Promo definition

    func testFactoryCreatesAutofillImportPromoWithCorrectConfiguration() {
        let promo = PromoServiceFactory.autofillImport(observer: sut)

        XCTAssertEqual(promo.id, "autofill-import-item")
        XCTAssertTrue(promo.triggers.isEmpty)
        XCTAssertEqual(promo.initiated, .user)
        XCTAssertEqual(promo.promoType.severity, .low)
        XCTAssertEqual(promo.context, .webPage)
        XCTAssertTrue(promo.coexistingPromoIDs.isEmpty)
        XCTAssertTrue(promo.delegate === sut)
    }

    // MARK: - Integration with PromoService

    func testWhenImportPromptClosedWithoutActionThenPromoServiceRecordsDismissalAndPromoStaysEligible() async {
        let record = await recordAfterPromoServiceRoundTrip(action: nil)

        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
        XCTAssertFalse(record.isPermanentlyDismissed)
        XCTAssertTrue(record.isEligible)
    }

    func testWhenImportStartedThenPromoServiceRecordsActionedAndPermanentlyDismissed() async {
        let record = await recordAfterPromoServiceRoundTrip(action: .startImport)

        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertTrue(record.actioned)
        XCTAssertTrue(record.isPermanentlyDismissed)
    }

    func testWhenPermanentlyDismissedThenPromoServiceRecordsPermanentDismissalWithoutAction() async {
        let record = await recordAfterPromoServiceRoundTrip(action: .permanentlyDismiss)

        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
        XCTAssertTrue(record.isPermanentlyDismissed)
    }

    private func recordAfterPromoServiceRoundTrip(action: Action?) async -> PromoHistoryRecord {
        let historyStore = MockPromoHistoryStore()
        let promoService = makePromoService(historyStore: historyStore)
        let visibleExpectation = XCTestExpectation(description: "autofill import promo visible")
        let hiddenExpectation = XCTestExpectation(description: "autofill import promo hidden")
        let resultExpectation = XCTestExpectation(description: "hide result persisted")
        var wasVisible = false
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == PromoServiceFactory.autofillImportPromoID }) {
                    wasVisible = true
                    visibleExpectation.fulfill()
                } else if wasVisible {
                    hiddenExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        promoService.historyPublisher(for: PromoServiceFactory.autofillImportPromoID)
            .compactMap { $0 }
            .sink { record in
                if record.timesDismissed == 1, record.lastDismissed != nil {
                    resultExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        startAndWaitForRegistration(promoService)
        sut.overlayDidShowImportPrompt(overlayA)
        await fulfillment(of: [visibleExpectation], timeout: 5.0)
        if let action {
            sut.perform(action, from: overlayA)
        }
        sut.overlayDidHideImportPrompt(overlayA)
        await fulfillment(of: [hiddenExpectation, resultExpectation], timeout: 5.0)

        return historyStore.record(for: PromoServiceFactory.autofillImportPromoID)
    }

    // PromoService subscribes to the delegate on its queue; a show reported mid-subscription can be missed.
    private func startAndWaitForRegistration(_ promoService: PromoService) {
        promoService.applicationDidBecomeActive()
        promoService.testQueue.sync {}
    }

    private func makePromoService(historyStore: MockPromoHistoryStore) -> PromoService {
        PromoService(
            promos: [PromoServiceFactory.autofillImport(observer: sut)],
            historyStore: historyStore,
            triggerPublisher: PassthroughSubject<PromoTrigger, Never>().eraseToAnyPublisher(),
            isOnboardingCompletedProvider: { true },
            stateQueue: DispatchQueue(label: "test.promoService.autofillImport"),
            evaluationDeferralWindow: 0,
            registrationFallbackTimeout: 0,
            externalActivationWindow: 0
        )
    }
}
