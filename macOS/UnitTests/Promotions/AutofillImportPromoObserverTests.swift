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
    /// An import step writes logins; `hasImportedLogins` flips before the flow ends.
    case importLogins
    case endImportFlow
    case permanentlyDismiss
}

private extension AutofillImportPromoObserver {
    @MainActor
    func perform(_ action: Action, from overlay: AnyObject, importState: MockAutofillLoginImportState) {
        switch action {
        case .startImport: overlayDidStartImport(overlay)
        case .importLogins: importState.hasImportedLogins = true
        case .endImportFlow: overlayDidEndImportFlow(overlay)
        case .permanentlyDismiss: overlayDidPermanentlyDismissImportPrompt(overlay)
        }
    }
}

@MainActor
final class AutofillImportPromoObserverTests: XCTestCase {

    private var sut: AutofillImportPromoObserver!
    private var importState: MockAutofillLoginImportState!
    private var cancellables: Set<AnyCancellable>!
    private var received: [Bool]!

    // Stand-ins for overlay view controllers; only their identity matters.
    private var overlayA: NSObject!
    private var overlayB: NSObject!

    override func setUp() {
        super.setUp()
        importState = MockAutofillLoginImportState()
        sut = AutofillImportPromoObserver(loginImportStateProvider: importState)
        cancellables = []
        received = []
        overlayA = NSObject()
        overlayB = NSObject()
    }

    override func tearDown() {
        cancellables = nil
        received = nil
        sut = nil
        importState = nil
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

        sut.overlayWillDisappear(overlayA)
        XCTAssertFalse(sut.isVisible)

        XCTAssertEqual(received, [false, true, false])
    }

    func testWhenSameOverlayShowsTwiceThenOneHideHidesIt() {
        recordEmissions()

        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayWillDisappear(overlayA)

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

        sut.overlayWillDisappear(overlayA)
        XCTAssertTrue(sut.isVisible, "A late hide from the replaced overlay must not hide the current one")
        XCTAssertEqual(received, [false, true, false, true])

        sut.overlayWillDisappear(overlayB)
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(received, [false, true, false, true, false])
    }

    func testWhenUnknownOrAlreadyHiddenOverlayHidesThenNothingChanges() {
        recordEmissions()

        sut.overlayWillDisappear(overlayA)
        sut.overlayDidShowImportPrompt(overlayB)
        sut.overlayWillDisappear(overlayA)
        XCTAssertTrue(sut.isVisible, "A stray hide must not hide another overlay's prompt")

        sut.overlayWillDisappear(overlayB)
        sut.overlayWillDisappear(overlayB)

        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(received, [false, true, false])
    }

    // MARK: - Import flow

    func testWhenOverlayDisappearsDuringImportThenPromoStaysVisibleUntilFlowEnds() {
        recordEmissions()
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidStartImport(overlayA)

        sut.overlayWillDisappear(overlayA)
        XCTAssertTrue(sut.isVisible, "Launching the import flow hides the overlay; the promo must wait for the import result")

        sut.overlayDidEndImportFlow(overlayA)
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(received, [false, true, false])
    }

    func testWhenLoginsAreImportedThenPromoClosesAsActionedWhenFlowEnds() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidStartImport(overlayA)
        sut.overlayWillDisappear(overlayA)

        importState.hasImportedLogins = true
        XCTAssertTrue(sut.isVisible, "The result is only resolved when the import flow ends")

        sut.overlayDidEndImportFlow(overlayA)

        XCTAssertFalse(sut.isVisible)
        XCTAssertEqual(sut.resultWhenHidden, .actioned)
    }

    func testWhenImportFlowEndsWithoutStartedImportThenNothingChanges() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidEndImportFlow(overlayA)

        XCTAssertTrue(sut.isVisible)
    }

    // MARK: - Result when hidden

    func testResultWhenHiddenForEachResolutionPath() {
        let cases: [(actions: [Action], hadImportedLogins: Bool, expected: PromoResult)] = [
            ([], false, .ignored(cooldown: 0)),
            ([.startImport, .importLogins, .endImportFlow], false, .actioned),
            ([.startImport, .endImportFlow], false, .ignored(cooldown: 0)),
            ([.startImport, .importLogins, .endImportFlow], true, .ignored(cooldown: 0)),
            ([.permanentlyDismiss], false, .ignored())
        ]

        for (actions, hadImportedLogins, expected) in cases {
            let importState = MockAutofillLoginImportState()
            importState.hasImportedLogins = hadImportedLogins
            let observer = AutofillImportPromoObserver(loginImportStateProvider: importState)
            observer.overlayDidShowImportPrompt(overlayA)
            actions.forEach { observer.perform($0, from: overlayA, importState: importState) }
            observer.overlayWillDisappear(overlayA)

            XCTAssertFalse(observer.isVisible, "\(actions), hadImportedLogins: \(hadImportedLogins)")
            XCTAssertEqual(observer.resultWhenHidden, expected, "\(actions), hadImportedLogins: \(hadImportedLogins)")
        }
    }

    func testWhenActionComesFromUntrackedOverlayThenItIsIgnored() {
        sut.overlayDidStartImport(overlayA)
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidStartImport(overlayB)
        sut.overlayDidPermanentlyDismissImportPrompt(overlayB)
        importState.hasImportedLogins = true
        sut.overlayDidEndImportFlow(overlayB)
        XCTAssertTrue(sut.isVisible)

        sut.overlayWillDisappear(overlayA)

        XCTAssertEqual(sut.resultWhenHidden, .ignored(cooldown: 0))
    }

    func testWhenReplacedOverlayWasPermanentlyDismissedThenItsOutcomeIsResolved() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidPermanentlyDismissImportPrompt(overlayA)
        sut.overlayDidShowImportPrompt(overlayB)

        XCTAssertEqual(sut.resultWhenHidden, .ignored())
    }

    func testWhenOverlayIsReplacedDuringImportThenImportIsNotCounted() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidStartImport(overlayA)
        sut.overlayDidShowImportPrompt(overlayB)
        XCTAssertEqual(sut.resultWhenHidden, .ignored(cooldown: 0))

        importState.hasImportedLogins = true
        sut.overlayDidEndImportFlow(overlayA)

        XCTAssertTrue(sut.isVisible, "A late flow end from the replaced overlay must not close the current one")
    }

    func testWhenNewStretchHasNoActionThenResultResets() {
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidPermanentlyDismissImportPrompt(overlayA)
        sut.overlayWillDisappear(overlayA)
        XCTAssertEqual(sut.resultWhenHidden, .ignored())

        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayWillDisappear(overlayA)

        XCTAssertEqual(sut.resultWhenHidden, .ignored(cooldown: 0))
    }

    func testWhenVisibilityBecomesFalseThenResultIsAlreadyResolved() {
        var resultWhenHiddenOnEmission: PromoResult?
        sut.overlayDidShowImportPrompt(overlayA)
        sut.overlayDidStartImport(overlayA)
        sut.isVisiblePublisher
            .filter { !$0 }
            .sink { [weak self] _ in resultWhenHiddenOnEmission = self?.sut.resultWhenHidden }
            .store(in: &cancellables)

        importState.hasImportedLogins = true
        sut.overlayDidEndImportFlow(overlayA)

        XCTAssertEqual(resultWhenHiddenOnEmission, .actioned)
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
        let record = await recordAfterPromoServiceRoundTrip(actions: [])

        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
        XCTAssertFalse(record.isPermanentlyDismissed)
        XCTAssertTrue(record.isEligible)
    }

    func testWhenLoginsImportedFromPromoThenPromoServiceRecordsActionedAndPermanentlyDismissed() async {
        let record = await recordAfterPromoServiceRoundTrip(actions: [.startImport, .importLogins, .endImportFlow])

        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertTrue(record.actioned)
        XCTAssertTrue(record.isPermanentlyDismissed)
    }

    func testWhenImportFromPromoAddsNoLoginsThenPromoServiceRecordsDismissalAndPromoStaysEligible() async {
        let record = await recordAfterPromoServiceRoundTrip(actions: [.startImport, .endImportFlow])

        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
        XCTAssertFalse(record.isPermanentlyDismissed)
        XCTAssertTrue(record.isEligible)
    }

    func testWhenPermanentlyDismissedThenPromoServiceRecordsPermanentDismissalWithoutAction() async {
        let record = await recordAfterPromoServiceRoundTrip(actions: [.permanentlyDismiss])

        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
        XCTAssertTrue(record.isPermanentlyDismissed)
    }

    private func recordAfterPromoServiceRoundTrip(actions: [Action]) async -> PromoHistoryRecord {
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
        actions.forEach { sut.perform($0, from: overlayA, importState: importState) }
        sut.overlayWillDisappear(overlayA)
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
