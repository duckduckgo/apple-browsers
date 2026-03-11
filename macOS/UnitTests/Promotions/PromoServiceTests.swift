//
//  PromoServiceTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

final class PromoServiceTests: XCTestCase {

    private var triggerSubject: PassthroughSubject<PromoTrigger, Never>!
    private var historyStore: MockPromoHistoryStore!
    private var testQueue: DispatchQueue!
    private var cancellables = Set<AnyCancellable>()
    private let timeout: TimeInterval = 5.0

    override func setUp() {
        super.setUp()
        triggerSubject = PassthroughSubject<PromoTrigger, Never>()
        historyStore = MockPromoHistoryStore()
        testQueue = DispatchQueue(label: "test.promoService")
    }

    override func tearDown() {
        triggerSubject = nil
        historyStore = nil
        testQueue = nil
        cancellables.removeAll()
        super.tearDown()
    }

    private func drainStateQueue() {
        let exp = XCTestExpectation(description: "stateQueue drained")
        testQueue.async { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    private func makeService(
        promos: [Promo],
        initialExternalActivation: Bool = false,
        evaluationDeferralWindow: TimeInterval = 0,
        registrationFallbackTimeout: TimeInterval = 0,
        externalActivationWindow: TimeInterval = 0
    ) -> PromoService {
        PromoService(
            promos: promos,
            historyStore: historyStore,
            triggerPublisher: triggerSubject.eraseToAnyPublisher(),
            initialExternalActivation: initialExternalActivation,
            stateQueue: testQueue,
            evaluationDeferralWindow: evaluationDeferralWindow,
            registrationFallbackTimeout: registrationFallbackTimeout,
            externalActivationWindow: externalActivationWindow
        )
    }

    // MARK: - Rule evaluation

    func testWhenOneMediumPromoVisible_ThenSecondMediumPromoIsSkipped() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        let delegate2 = MockPromoDelegate(isEligible: true)
        delegate2.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "promo-1", delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "promo-2", delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "promo-2" }) {
                    XCTFail("Second promo should not be shown")
                } else if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        delegate1.completeShow(with: .actioned)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 0)
        XCTAssertEqual(historyStore.saveCallCount, 2) // lastShown stamp + result
    }

    func testWhenTwoMediumPromosHaveMutualCoexistingIds_ThenBothCanBeVisible() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        let delegate2 = MockPromoDelegate(isEligible: true)
        let promo1 = PromoTestHelpers.makePromo(id: "coexist-a", coexistingPromoIDs: ["coexist-b"], delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "coexist-b", coexistingPromoIDs: ["coexist-a"], delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let bothShownExpectation = XCTestExpectation(description: "both promos shown")
        let hideExpectation = XCTestExpectation(description: "promos are hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "coexist-a" }) && promos.contains(where: { $0.id == "coexist-b" }) {
                    bothShownExpectation.fulfill()
                }
                if promos.isEmpty {
                    hideExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [bothShownExpectation], timeout: timeout)
        delegate1.completeShow(with: .actioned)
        delegate2.completeShow(with: .actioned)
        await fulfillment(of: [hideExpectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 1)
    }

    func testWhenExternalActivationIsTrue_ThenAllPromosSuppressed() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo], initialExternalActivation: true, externalActivationWindow: 0.1)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
        XCTAssertEqual(historyStore.saveCallCount, 0)
    }

    func testWhenLowSeverityPromo_ThenSkipsAllRulesIncludingExternalActivation() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "low-promo", promoType: PromoType(.inlineMessage), delegate: delegate)
        let promoService = makeService(promos: [promo], initialExternalActivation: true)
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenGlobalPromoVisible_ThenOtherContextPromoBlocked() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        delegate1.setShowResult(.noChange)
        let delegate2 = MockPromoDelegate(isEligible: true)
        delegate2.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "global", context: .global, delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "ntp", context: .newTabPage, delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.context == .newTabPage }) {
                    XCTFail("New tab page context should be blocked by global context promo")
                } else if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        triggerSubject.send(.newTabPageAppeared)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 0)
    }

    func testWhenTwoSameContextPromosHaveMutualCoexistingIds_ThenBothCanBeVisible() async {
        // Given: two newTabPage promos with mutual coexistence
        let delegate1 = MockPromoDelegate(isEligible: true)
        let delegate2 = MockPromoDelegate(isEligible: true)
        let triggers: Set<PromoTrigger> = [.appLaunched, .newTabPageAppeared]
        let promo1 = PromoTestHelpers.makePromo(id: "ntp-a", triggers: triggers, context: .newTabPage, coexistingPromoIDs: ["ntp-b"], delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "ntp-b", triggers: triggers, context: .newTabPage, coexistingPromoIDs: ["ntp-a"], delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let bothShownExpectation = XCTestExpectation(description: "both promos shown")
        let hideExpectation = XCTestExpectation(description: "promos are hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "ntp-a" }) && promos.contains(where: { $0.id == "ntp-b" }) {
                    bothShownExpectation.fulfill()
                }
                if promos.isEmpty {
                    hideExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        triggerSubject.send(.newTabPageAppeared)
        await fulfillment(of: [bothShownExpectation], timeout: timeout)
        delegate1.completeShow(with: .actioned)
        delegate2.completeShow(with: .actioned)
        await fulfillment(of: [hideExpectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 1)
    }

    func testWhenCoexistingPromoBVisible_ThenPromoCWithoutCoexistenceWithBIsBlocked() async {
        // Given: A coexists with B, B coexists with A. C does not coexist with B. B is visible.
        let delegateA = MockPromoDelegate(isEligible: true)
        let delegateB = MockPromoDelegate(isEligible: true)
        let delegateC = MockPromoDelegate(isEligible: true)
        let promoA = PromoTestHelpers.makePromo(id: "promo-a", coexistingPromoIDs: ["promo-b"], delegate: delegateA)
        let promoB = PromoTestHelpers.makePromo(id: "promo-b", coexistingPromoIDs: ["promo-a"], delegate: delegateB)
        let promoC = PromoTestHelpers.makePromo(id: "promo-c", coexistingPromoIDs: [], delegate: delegateC)
        let promoService = makeService(promos: [promoA, promoB, promoC])
        let showBExpectation = XCTestExpectation(description: "B is shown")
        let hideExpectation = XCTestExpectation(description: "all hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "promo-b" }) && !promos.contains(where: { $0.id == "promo-c" }) {
                    showBExpectation.fulfill()
                }
                if promos.isEmpty {
                    hideExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: show A and B (they coexist), C is blocked when evaluated
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showBExpectation], timeout: timeout)
        delegateA.completeShow(with: .actioned)
        delegateB.completeShow(with: .actioned)
        await fulfillment(of: [hideExpectation], timeout: timeout)

        // Then: C was never shown
        XCTAssertEqual(delegateC.hideCallCount, 0)
    }

    func testWhenAppInitiatedPromoDismissedRecently_ThenGlobalCooldownBlocksNextAppPromo() async {
        // Given: promo-1 was dismissed 1 hour ago, cooldown is 24h
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var record = PromoHistoryRecord(id: "cooldown-promo")
        record.lastDismissed = oneHourAgo
        record.timesDismissed = 1
        historyStore = MockPromoHistoryStore(records: ["cooldown-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "cooldown-promo", initiated: .app, delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then: promo was not shown (blocked by global cooldown)
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    func testWhenLowSeverityPromoSetsGlobalCooldown_ThenDoesNotBlockMediumPromo() async {
        // Given: low-severity promo A (setsGlobalCooldown) was dismissed; medium promo B should not be blocked
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var recordA = PromoHistoryRecord(id: "low-severity-a")
        recordA.lastDismissed = oneHourAgo
        recordA.timesDismissed = 1
        historyStore = MockPromoHistoryStore(records: ["low-severity-a": recordA])
        let delegateA = MockPromoDelegate(isEligible: false)
        let delegateB = MockPromoDelegate(isEligible: true)
        delegateB.setShowResult(.actioned)
        let promoA = PromoTestHelpers.makePromo(id: "low-severity-a", promoType: PromoType(.inlineTip), setsGlobalCooldown: true, delegate: delegateA)
        let promoB = PromoTestHelpers.makePromo(id: "medium-severity-b", delegate: delegateB)
        let promoService = makeService(promos: [promoA, promoB])
        let expectation = XCTestExpectation(description: "promo b shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if !promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: B was shown (low-severity A's dismissal does not contribute to global cooldown)
        XCTAssertEqual(delegateB.showCallCount, 1)
    }

    func testWhenPromoAlreadyVisible_ThenSameTriggerDoesNotStartDuplicateShow() async {
        // Given: delegate does not complete show immediately, so promo stays in activeSessions
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "duplicate-guard-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let showExpectation = XCTestExpectation(description: "promo shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if !promos.isEmpty {
                    showExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: trigger fires twice while promo is visible (show has not completed)
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showExpectation], timeout: timeout)
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then: show was invoked only once (second trigger skipped due to already-visible guard)
        XCTAssertEqual(delegate.showCallCount, 1)
        delegate.completeShow(with: .noChange)
        drainStateQueue()
    }

    func testWhenTriggerDoesNotMatchPromoTriggers_ThenPromoNotEvaluated() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "ntp-only", triggers: [.newTabPageAppeared], delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.windowBecameKey)
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
        XCTAssertEqual(delegate.refreshEligibilityCallCount, 0)
    }

    func testWhenMultiplePromosMatchTrigger_ThenHighestPrioritySelected() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        delegate1.setShowResult(.actioned)
        let delegate2 = MockPromoDelegate(isEligible: true)
        delegate2.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "high-priority", delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "low-priority", delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 0)
    }

    func testWhenActionedResult_ThenPermanentlyDismissed() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "actioned-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let record = historyStore.record(for: "actioned-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertTrue(record.actioned)
    }

    func testWhenIgnoredWithCooldown_ThenTemporaryCooldownSet() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.ignored(cooldown: 86400))
        let promo = PromoTestHelpers.makePromo(id: "cooldown-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let record = historyStore.record(for: "cooldown-promo")
        XCTAssertNotNil(record.nextEligibleDate)
        XCTAssertNotEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
    }

    func testWhenIgnoredWithNilCooldown_ThenPermanentlyDismissed() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.ignored(cooldown: nil))
        let promo = PromoTestHelpers.makePromo(id: "ignored-nil-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        let record = historyStore.record(for: "ignored-nil-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
    }

    func testWhenNoneResult_ThenNoStateChange() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.noChange)
        let promo = PromoTestHelpers.makePromo(id: "none-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then
        let record = historyStore.record(for: "none-promo")
        XCTAssertEqual(record.timesDismissed, 0)
        XCTAssertNil(record.lastDismissed)
        XCTAssertFalse(record.actioned)
    }

    func testWhenDismissNonVisiblePromo_ThenHistoryUpdated() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "dismiss-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        promoService.dismiss(promoId: "dismiss-promo", result: .actioned)
        drainStateQueue()

        // Then
        let record = historyStore.record(for: "dismiss-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertTrue(record.actioned)
    }

    func testWhenUndismissWithClearHistory_ThenResetsAllHistoryFields() async {
        // Given
        var record = PromoHistoryRecord(id: "undismiss-promo")
        record.timesDismissed = 2
        record.lastDismissed = Date()
        record.lastShown = Date()
        record.nextEligibleDate = .distantFuture
        record.actioned = true
        historyStore = MockPromoHistoryStore(records: ["undismiss-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "undismiss-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        promoService.undismiss(promoId: "undismiss-promo", clearHistory: true)
        drainStateQueue()

        // Then: all history fields reset
        let loaded = historyStore.record(for: "undismiss-promo")
        XCTAssertEqual(loaded.timesDismissed, 0)
        XCTAssertNil(loaded.lastDismissed)
        XCTAssertNil(loaded.lastShown)
        XCTAssertNil(loaded.nextEligibleDate)
        XCTAssertFalse(loaded.actioned)
    }

    func testWhenUndismissWithClearHistoryFalse_ThenPreservesTimesDismissedAndLastShown() async {
        // Given
        let lastShownDate = Date()
        var record = PromoHistoryRecord(id: "undismiss-preserve-promo")
        record.timesDismissed = 3
        record.lastDismissed = Date()
        record.lastShown = lastShownDate
        record.nextEligibleDate = .distantFuture
        record.actioned = true
        historyStore = MockPromoHistoryStore(records: ["undismiss-preserve-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "undismiss-preserve-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        promoService.undismiss(promoId: "undismiss-preserve-promo", clearHistory: false)
        drainStateQueue()

        // Then: lastDismissed and nextEligibleDate cleared; timesDismissed, lastShown, actioned preserved
        let loaded = historyStore.record(for: "undismiss-preserve-promo")
        XCTAssertEqual(loaded.timesDismissed, 3)
        XCTAssertNil(loaded.lastDismissed)
        XCTAssertNil(loaded.nextEligibleDate)
        XCTAssertEqual(loaded.lastShown, lastShownDate)
        XCTAssertTrue(loaded.actioned)
    }

    // MARK: - Delegate readiness

    func testWhenAllDelegatesSetBeforeStart_ThenCompleteRegistrationFiresImmediately() async {
        // Given: all promos have delegates from init
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: promo was shown (registration completed immediately, trigger was processed)
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenNotAllDelegatesSet_ThenFallbackTimeoutCompletesRegistration() async {
        // Given: one promo without delegate
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promoWithDelegate = PromoTestHelpers.makePromo(id: "with-delegate", delegate: delegate)
        let promoWithoutDelegate = PromoTestHelpers.makePromo(id: "without-delegate", delegate: nil)
        let promoService = makeService(promos: [promoWithoutDelegate, promoWithDelegate], registrationFallbackTimeout: 0.05)
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: trigger before fallback, then wait for fallback
        triggerSubject.send(.appLaunched)
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: promo with delegate was shown after fallback completed registration
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenDelegateSetAfterStart_ThenCompleteRegistrationRunsImmediately() async {
        // Given: one promo without delegate
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "late-delegate", delegate: nil)
        let promoService = makeService(promos: [promo], registrationFallbackTimeout: 1.0)
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        promoService.setDelegate(for: "late-delegate", delegate: delegate)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: registration completed via setDelegate, buffered trigger was processed
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenCompleteRegistrationCalledTwice_ThenIdempotent() async {
        // Given: all delegates set
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: applicationDidBecomeActive triggers registration; setDelegate again (no-op, already set)
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        promoService.setDelegate(for: "test-promo", delegate: delegate)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: only one show (no double processing)
        XCTAssertEqual(delegate.showCallCount, 1)
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenTriggersArriveBeforeRegistration_ThenBufferedAndProcessedAfter() async {
        // Given: trigger sent before applicationDidBecomeActive
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: trigger first, then activate (trigger gets buffered, processed when deferral runs)
        triggerSubject.send(.appLaunched)
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenExternallyActivatedAtRegistration_ThenBufferedTriggersDiscarded() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo], initialExternalActivation: true, externalActivationWindow: 1.0)
        let expectation = XCTestExpectation(description: "no promo shown")
        expectation.isInverted = true
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if !promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        triggerSubject.send(.appLaunched)
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then: promo was never shown (buffered triggers discarded due to external activation)
        await fulfillment(of: [expectation], timeout: 0.5)
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    func testWhenPromoWithoutDelegate_ThenSkippedDuringEvaluation() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promoWithDelegate = PromoTestHelpers.makePromo(id: "with-delegate", delegate: delegate)
        let promoWithoutDelegate = PromoTestHelpers.makePromo(id: "without-delegate", delegate: nil)
        let promoService = makeService(promos: [promoWithoutDelegate, promoWithDelegate])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    // MARK: - Cooldown options

    func testWhenRespectsGlobalCooldownFalse_ThenCanShowDuringCooldown() async {
        // Given: other-promo dismissed 1h ago (sets cooldown). bypass-cooldown has respectsGlobalCooldown: false
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var otherRecord = PromoHistoryRecord(id: "other-promo")
        otherRecord.lastDismissed = oneHourAgo
        otherRecord.timesDismissed = 1
        historyStore = MockPromoHistoryStore(records: ["other-promo": otherRecord])
        let delegateOther = MockPromoDelegate(isEligible: true)
        delegateOther.setShowResult(.actioned)
        let delegateBypass = MockPromoDelegate(isEligible: true)
        delegateBypass.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "other-promo", delegate: delegateOther)
        let promo2 = PromoTestHelpers.makePromo(id: "bypass-cooldown", respectsGlobalCooldown: false, delegate: delegateBypass)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "bypass promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: bypass-cooldown was shown despite global cooldown from other-promo
        XCTAssertEqual(delegateBypass.hideCallCount, 1)
        XCTAssertEqual(delegateOther.hideCallCount, 0)
    }

    func testWhenSetsGlobalCooldownFalse_ThenDismissalDoesNotContributeToCooldown() async {
        // Given: promo A has setsGlobalCooldown: false, promo B has default
        let delegateA = MockPromoDelegate(isEligible: true)
        delegateA.setShowResult(.actioned)
        let delegateB = MockPromoDelegate(isEligible: true)
        let promoA = PromoTestHelpers.makePromo(id: "no-cooldown-a", setsGlobalCooldown: false, delegate: delegateA)
        let promoB = PromoTestHelpers.makePromo(id: "cooldown-b", delegate: delegateB)
        let promoService = makeService(promos: [promoA, promoB])
        let hideExpectation = XCTestExpectation(description: "promo a hidden")
        let showExpectation = XCTestExpectation(description: "promo b shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    hideExpectation.fulfill()
                } else if promos.contains(where: { $0.id == "cooldown-b" }) {
                    showExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: show A, dismiss A, trigger again - B should show (A's dismiss didn't set cooldown)
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [hideExpectation], timeout: timeout)
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showExpectation], timeout: timeout)

        // Then: B was shown (A's dismissal didn't block it)
        XCTAssertEqual(delegateB.showCallCount, 1)
    }

    func testWhenDefaultCooldownOptions_ThenStandardCooldownBehavior() async {
        // Given: default respectsGlobalCooldown and setsGlobalCooldown
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "default-cooldown", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo dismissed")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: record has nextEligibleDate set (permanent dismiss)
        let record = historyStore.record(for: "default-cooldown")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
    }

    func testWhenRefreshEligibilityCalled_ThenDelegateRefreshEligibilityInvoked() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertGreaterThan(delegate.refreshEligibilityCallCount, 0)
    }

    // MARK: - Timeout and eligibility

    func testWhenTimeoutFiresBeforeShowReturns_ThenTimeoutResultRecorded() async {
        // Given: promo with short timeout
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(
            id: "timeout-promo",
            promoType: PromoType(.inlineMessage, customTimeoutInterval: 0.05, customTimeoutResult: .actioned),
            delegate: delegate
        )
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo hidden after timeout")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        let record = historyStore.record(for: "timeout-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertTrue(record.actioned)
    }

    func testWhenShowReturnsBeforeTimeout_ThenTimeoutCancelled() async {
        // Given: promo with long timeout, show returns quickly
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.ignored(cooldown: 3600))
        let promo = PromoTestHelpers.makePromo(
            id: "show-first-promo",
            promoType: PromoType(.inlineMessage, customTimeoutInterval: 10, customTimeoutResult: .actioned),
            delegate: delegate
        )
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: show result (.ignored) recorded, not timeout result
        let record = historyStore.record(for: "show-first-promo")
        XCTAssertNotEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertFalse(record.actioned)
    }

    func testWhenEligibilityLostDuringShow_ThenHideCalledAndNoneRecorded() async {
        // Given: show suspends, we flip eligibility to false
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "eligibility-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let showExpectation = XCTestExpectation(description: "promo shown")
        let hideExpectation = XCTestExpectation(description: "promo hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if !promos.isEmpty {
                    showExpectation.fulfill()
                } else {
                    hideExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showExpectation], timeout: timeout)
        delegate.setEligible(false)
        await fulfillment(of: [hideExpectation], timeout: timeout)

        let record = historyStore.record(for: "eligibility-promo")
        XCTAssertEqual(record.timesDismissed, 0)
        XCTAssertNil(record.lastDismissed)
        XCTAssertFalse(record.actioned)
    }

    func testWhenVisiblePromosPersisted_ThenRestoredOnNextLaunch() async {
        // Given: record with lastShown set and no lastDismissed (was visible at shutdown)
        var record = PromoHistoryRecord(id: "restore-promo")
        record.lastShown = Date()
        historyStore.save(record)
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.noChange)
        let promo = PromoTestHelpers.makePromo(id: "restore-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    // MARK: - Restore on restart

    func testWhenLastShownGreaterThanLastDismissed_ThenPromoIsRestored() async {
        // Given: lastShown > lastDismissed (promo was shown after last dismiss, still visible at shutdown)
        let earlier = Date().addingTimeInterval(-3600)
        let later = Date().addingTimeInterval(-1800)
        var record = PromoHistoryRecord(id: "restore-after-dismiss")
        record.lastDismissed = earlier
        record.lastShown = later
        historyStore = MockPromoHistoryStore(records: ["restore-after-dismiss": record])
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.noChange)
        let promo = PromoTestHelpers.makePromo(id: "restore-after-dismiss", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenLastDismissedGreaterThanOrEqualToLastShown_ThenPromoIsNotRestored() async {
        // Given: lastDismissed >= lastShown (promo was dismissed after last show, not visible at shutdown)
        let earlier = Date().addingTimeInterval(-3600)
        let later = Date().addingTimeInterval(-1800)
        var record = PromoHistoryRecord(id: "no-restore-dismissed-after-show")
        record.lastShown = earlier
        record.lastDismissed = later
        historyStore = MockPromoHistoryStore(records: ["no-restore-dismissed-after-show": record])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "no-restore-dismissed-after-show", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    func testWhenNoLastShown_ThenPromoIsNotRestored() async {
        // Given: record has no lastShown (never shown or from old schema)
        var record = PromoHistoryRecord(id: "no-last-shown")
        record.lastDismissed = nil
        historyStore = MockPromoHistoryStore(records: ["no-last-shown": record])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "no-last-shown", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    func testWhenPerformShow_ThenLastShownIsStampedOnRecord() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "stamp-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then: record should have lastShown set after show
        let record = historyStore.record(for: "stamp-promo")
        XCTAssertNotNil(record.lastShown)
    }

    func testWhenRestorePromoNotEligible_ThenSlotFreedWithoutResult() async {
        // Given: record with lastShown set (was visible at shutdown) but delegate reports ineligible
        var record = PromoHistoryRecord(id: "ineligible-restore")
        record.lastShown = Date()
        historyStore.save(record)
        let delegate = MockPromoDelegate(isEligible: false)
        let promo = PromoTestHelpers.makePromo(id: "ineligible-restore", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    // MARK: - Debug and visiblePromosPublisher

    func testWhenVisiblePromosPublisher_ThenEmitsOnShowAndHide() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "publisher-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        var emissions: [[String]] = []
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                emissions.append(promos.map { $0.id })
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertTrue(emissions.contains { $0 == ["publisher-promo"] })
        XCTAssertTrue(emissions.contains { $0.isEmpty })
    }

    func testWhenRecordWithLastShownExistsForPromoNotInList_ThenSkippedWithoutError() async {
        // Given: history has record for "orphan-promo" (from removed feature) with lastShown set
        var orphanRecord = PromoHistoryRecord(id: "orphan-promo")
        orphanRecord.lastShown = Date()
        historyStore = MockPromoHistoryStore(records: ["orphan-promo": orphanRecord])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "current-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then: we only iterate over promos in list; orphan record is never considered, no crash
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    // MARK: - External delegate

    func testWhenExternalDelegateVisibilityTrue_ThenPromoAppearsInVisibleAndLastShownStamped() async {
        let externalDelegate = MockExternalPromoDelegate(initialVisibility: false)
        let promo = PromoTestHelpers.makePromo(id: "external-promo", delegate: externalDelegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "external promo visible")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "external-promo" }) {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        drainStateQueue()
        externalDelegate.setVisible(true)
        drainStateQueue()

        await fulfillment(of: [expectation], timeout: timeout)
        let record = historyStore.record(for: "external-promo")
        XCTAssertNotNil(record.lastShown)
    }

    func testWhenExternalDelegateVisibilityFalse_ThenPromoRemovedAndFixedResultApplied() async {
        let externalDelegate = MockExternalPromoDelegate(initialVisibility: true)
        let promo = PromoTestHelpers.makePromo(id: "external-dismiss-promo", delegate: externalDelegate)
        let promoService = makeService(promos: [promo])
        let visibleExpectation = XCTestExpectation(description: "external promo visible")
        let hiddenExpectation = XCTestExpectation(description: "external promo hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "external-dismiss-promo" }) {
                    visibleExpectation.fulfill()
                }
                if promos.isEmpty {
                    hiddenExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        drainStateQueue()
        await fulfillment(of: [visibleExpectation], timeout: timeout)
        externalDelegate.setVisible(false)
        drainStateQueue()
        await fulfillment(of: [hiddenExpectation], timeout: timeout)

        let record = historyStore.record(for: "external-dismiss-promo")
        XCTAssertEqual(record.timesDismissed, 1)
        XCTAssertNotNil(record.lastDismissed)
    }

    func testWhenExternalAndInternalPromosMatchTrigger_ThenOnlyInternalGetsShow() async {
        let externalDelegate = MockExternalPromoDelegate(initialVisibility: false)
        let internalDelegate = MockPromoDelegate(isEligible: true)
        internalDelegate.setShowResult(.actioned)
        let externalPromo = PromoTestHelpers.makePromo(id: "external-trigger", delegate: externalDelegate)
        let internalPromo = PromoTestHelpers.makePromo(id: "internal-trigger", delegate: internalDelegate)
        let promoService = makeService(promos: [externalPromo, internalPromo])
        let expectation = XCTestExpectation(description: "internal promo hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        XCTAssertEqual(internalDelegate.showCallCount, 1)
    }

    func testWhenExternalPromoVisible_ThenBlocksInternalPromoInSameContext() async {
        // Given
        let externalDelegate = MockExternalPromoDelegate(initialVisibility: true)
        let internalDelegate = MockPromoDelegate(isEligible: true)
        internalDelegate.setShowResult(.actioned)
        let externalPromo = PromoTestHelpers.makePromo(id: "external-block", context: .global, delegate: externalDelegate)
        let internalPromo = PromoTestHelpers.makePromo(id: "internal-blocked", context: .global, delegate: internalDelegate)
        let promoService = makeService(promos: [externalPromo, internalPromo])
        let notShownExpectation = XCTestExpectation(description: "internal promo not shown")
        notShownExpectation.isInverted = true
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "internal-blocked" }) {
                    notShownExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [notShownExpectation], timeout: 0.5)

        // Then
        XCTAssertEqual(internalDelegate.showCallCount, 0)
    }

    func testWhenExternalDelegateInitiallyVisibleAtRegistration_ThenBufferedTriggerEvaluationSeesInitialState() async {
        // Given: external promo is already visible when registration runs; internal promo should be blocked
        let externalDelegate = MockExternalPromoDelegate(initialVisibility: true)
        let internalDelegate = MockPromoDelegate(isEligible: true)
        internalDelegate.setShowResult(.actioned)
        let externalPromo = PromoTestHelpers.makePromo(id: "initially-visible-external", context: .global, delegate: externalDelegate)
        let internalPromo = PromoTestHelpers.makePromo(id: "blocked-internal", context: .global, delegate: internalDelegate)
        let promoService = makeService(promos: [externalPromo, internalPromo])
        let notShownExpectation = XCTestExpectation(description: "internal promo never shown")
        notShownExpectation.isInverted = true
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "blocked-internal" }) {
                    notShownExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Trigger is sent before activation; gets buffered and evaluated after deferral and registration
        triggerSubject.send(.appLaunched)
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [notShownExpectation], timeout: 0.5)

        // Then: external promo's initial state was already applied when buffered triggers were evaluated
        XCTAssertEqual(internalDelegate.showCallCount, 0)
    }

    func testWhenDismissExternalPromo_ThenRemovedFromVisibleAndResultApplied() async {
        let externalDelegate = MockExternalPromoDelegate(initialVisibility: true)
        let promo = PromoTestHelpers.makePromo(id: "external-dismiss-call", delegate: externalDelegate)
        let promoService = makeService(promos: [promo])
        let visibleExpectation = XCTestExpectation(description: "external promo visible")
        let hiddenExpectation = XCTestExpectation(description: "external promo hidden after dismiss")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "external-dismiss-call" }) {
                    visibleExpectation.fulfill()
                }
                if promos.isEmpty {
                    hiddenExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        drainStateQueue()
        await fulfillment(of: [visibleExpectation], timeout: timeout)
        promoService.dismiss(promoId: "external-dismiss-call", result: .actioned)
        drainStateQueue()
        await fulfillment(of: [hiddenExpectation], timeout: timeout)

        let record = historyStore.record(for: "external-dismiss-call")
        XCTAssertTrue(record.actioned)
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
    }

    func testWhenSetDelegateWithExternalDelegate_ThenSubscriptionEstablishedAndInitialVisibilityReflected() async {
        let externalDelegate = MockExternalPromoDelegate(initialVisibility: true)
        let promo = PromoTestHelpers.makePromo(id: "late-external", delegate: nil)
        let promoService = makeService(promos: [promo], registrationFallbackTimeout: 1.0)
        let expectation = XCTestExpectation(description: "external promo visible after setDelegate")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "late-external" }) {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        promoService.setDelegate(for: "late-external", delegate: externalDelegate)
        drainStateQueue()

        await fulfillment(of: [expectation], timeout: timeout)
        let record = historyStore.record(for: "late-external")
        XCTAssertNotNil(record.lastShown)
    }

    // MARK: - PromoHistoryProviding

    func testWhenHistoryStoreHasPreExistingRecord_ThenHistoryPublisherEmitsItOnStart() async {
        // Given: pre-populated record for seed-promo
        var record = PromoHistoryRecord(id: "seed-promo")
        record.timesDismissed = 2
        record.lastDismissed = Date()
        historyStore = MockPromoHistoryStore(records: ["seed-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "seed-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        var emissions: [PromoHistoryRecord?] = []
        let expectation = XCTestExpectation(description: "history publisher emitted")
        promoService.historyPublisher(for: "seed-promo")
            .sink { record in
                emissions.append(record)
                if let record, record.timesDismissed == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertFalse(emissions.isEmpty)
        XCTAssertEqual(emissions.first??.timesDismissed, 2)
    }

    func testWhenPromoActioned_ThenHistoryPublisherEmitsUpdatedRecord() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "actioned-history-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        var emissions: [PromoHistoryRecord?] = []
        let expectation = XCTestExpectation(description: "history publisher emitted updated record")
        promoService.historyPublisher(for: "actioned-history-promo")
            .sink { record in
                emissions.append(record)
                if let record, record.actioned, record.nextEligibleDate == .distantFuture, record.timesDismissed == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let finalRecord = emissions.last.flatMap { $0 }
        XCTAssertNotNil(finalRecord)
        XCTAssertTrue(finalRecord?.actioned ?? false)
        XCTAssertEqual(finalRecord?.nextEligibleDate, .distantFuture)
        XCTAssertEqual(finalRecord?.timesDismissed, 1)
    }

    func testWhenUndismissCalled_ThenHistoryPublisherEmitsUpdatedRecord() async {
        // Given: permanently dismissed record
        var record = PromoHistoryRecord(id: "undismiss-history-promo")
        record.timesDismissed = 2
        record.lastDismissed = Date()
        record.nextEligibleDate = .distantFuture
        historyStore = MockPromoHistoryStore(records: ["undismiss-history-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "undismiss-history-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        var emissions: [PromoHistoryRecord?] = []
        let expectation = XCTestExpectation(description: "history publisher emitted updated record")
        promoService.historyPublisher(for: "undismiss-history-promo")
            .sink { record in
                emissions.append(record)
                if let record, record.nextEligibleDate == nil, record.timesDismissed == 0 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        promoService.undismiss(promoId: "undismiss-history-promo", clearHistory: true)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let finalRecord = emissions.last.flatMap { $0 }
        XCTAssertNotNil(finalRecord)
        XCTAssertNil(finalRecord?.nextEligibleDate)
        XCTAssertEqual(finalRecord?.timesDismissed, 0)
    }

    func testWhenUnrelatedPromoActioned_ThenHistoryPublisherDoesNotReEmitForOtherPromo() async {
        // Given: two promos with different triggers
        let delegateA = MockPromoDelegate(isEligible: true)
        let delegateB = MockPromoDelegate(isEligible: true)
        delegateB.setShowResult(.actioned)
        let promoA = PromoTestHelpers.makePromo(id: "promo-a", triggers: [.newTabPageAppeared], delegate: delegateA)
        let promoB = PromoTestHelpers.makePromo(id: "promo-b", triggers: [.appLaunched], delegate: delegateB)
        let promoService = makeService(promos: [promoA, promoB])
        let shownExpectation = XCTestExpectation(description: "promo-a shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    shownExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Show promo-A and let it complete with .noChange
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.newTabPageAppeared)
        delegateA.completeShow(with: .noChange)
        await fulfillment(of: [shownExpectation], timeout: timeout)

        // Subscribe to promo-A's history AFTER its own show cycle is done
        var emissions: [PromoHistoryRecord?] = []
        promoService.historyPublisher(for: "promo-a")
            .sink { record in
                emissions.append(record)
            }
            .store(in: &cancellables)

        // When: show B (actioned)
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then: exactly one emission for promo-a (subscription snapshot), no re-emit when B was actioned
        XCTAssertEqual(emissions.count, 1)
    }

    func testWhenHistoryStoreHasPreExistingRecords_ThenAllHistoryPublisherEmitsThemOnStart() async {
        // Given: two pre-populated records
        var record1 = PromoHistoryRecord(id: "all-seed-a")
        record1.timesDismissed = 1
        var record2 = PromoHistoryRecord(id: "all-seed-b")
        record2.timesDismissed = 2
        historyStore = MockPromoHistoryStore(records: ["all-seed-a": record1, "all-seed-b": record2])
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "all-seed-a", delegate: delegate)
        let promo2 = PromoTestHelpers.makePromo(id: "all-seed-b", delegate: delegate)
        let promoService = makeService(promos: [promo1, promo2])
        var emissions: [[PromoHistoryRecord]] = []
        let expectation = XCTestExpectation(description: "all history publisher emitted")
        promoService.allHistoryPublisher
            .sink { records in
                emissions.append(records)
                if records.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let ids = emissions.first?.map { $0.id }.sorted() ?? []
        XCTAssertEqual(ids, ["all-seed-a", "all-seed-b"])
    }

    func testWhenPromoActioned_ThenAllHistoryPublisherEmitsUpdatedArray() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "all-actioned-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        var emissions: [[PromoHistoryRecord]] = []
        let expectation = XCTestExpectation(description: "all history publisher emitted updated record")
        promoService.allHistoryPublisher
            .sink { records in
                emissions.append(records)
                if let record = records.first(where: { $0.id == "all-actioned-promo" }),
                   record.actioned,
                   record.nextEligibleDate == .distantFuture {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let finalRecords = emissions.last ?? []
        let record = finalRecords.first { $0.id == "all-actioned-promo" }
        XCTAssertNotNil(record)
        XCTAssertTrue(record?.actioned ?? false)
        XCTAssertEqual(record?.nextEligibleDate, .distantFuture)
    }
}
