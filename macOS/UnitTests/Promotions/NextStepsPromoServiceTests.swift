//
//  NextStepsPromoServiceTests.swift
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
import NewTabPage
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NextStepsPromoServiceTests: XCTestCase {

    private var triggerSubject: PassthroughSubject<PromoTrigger, Never>!
    private var historyStore: MockPromoHistoryStore!
    private var testQueue: DispatchQueue!
    private var cancellables = Set<AnyCancellable>()
    private let timeout: TimeInterval = 5.0

    override func setUp() {
        super.setUp()
        triggerSubject = PassthroughSubject<PromoTrigger, Never>()
        historyStore = MockPromoHistoryStore()
        testQueue = DispatchQueue(label: "test.nextStepsPromo")
    }

    override func tearDown() {
        triggerSubject = nil
        historyStore = nil
        testQueue = nil
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - makeNextStepsPromos

    @MainActor
    func testMakeNextStepsPromos_ReturnsOnePromoWithExpectedMetadata() {
        let promos = PromoServiceFactory.makeNextStepsPromos()
        XCTAssertEqual(promos.count, 1)
        let promo = promos[0]
        XCTAssertEqual(promo.id, "next-steps-cards")
        XCTAssertEqual(promo.triggers, [.newTabPageAppeared])
        XCTAssertEqual(promo.initiated, .app)
        XCTAssertEqual(promo.context, .newTabPage)
        XCTAssertTrue(promo.coexistingPromoIDs.contains("remote-message-ntp"))
        XCTAssertTrue(promo.coexistingPromoIDs.contains("remote-message-tabbar"))
        XCTAssertEqual(promo.coexistingPromoIDs.count, 2)
        XCTAssertNil(promo.delegate)
    }

    // MARK: - Coexistence with RMF

    func testWhenNextStepsAndRMFNtpHaveMutualCoexistingIds_ThenBothCanBeVisible() async {
        let nextStepsDelegate = MockPromoDelegate(isEligible: true)
        nextStepsDelegate.setShowResult(.noChange)
        let nextStepsPromo = PromoTestHelpers.makePromo(
            id: "next-steps-cards",
            triggers: [.newTabPageAppeared],
            promoType: PromoType(.nextSteps),
            context: .newTabPage,
            coexistingPromoIDs: ["remote-message-ntp", "remote-message-tabbar"],
            delegate: nextStepsDelegate
        )

        let rmfDelegate = MockPromoDelegate(isEligible: true)
        rmfDelegate.setShowResult(.noChange)
        let rmfPromo = PromoTestHelpers.makePromo(
            id: "remote-message-ntp",
            triggers: [.newTabPageAppeared],
            promoType: PromoType(.remoteMessage),
            context: .newTabPage,
            coexistingPromoIDs: ["remote-message-tabbar", "next-steps-cards"],
            respectsGlobalCooldown: false,
            delegate: rmfDelegate
        )

        let promoService = PromoService(
            promos: [rmfPromo, nextStepsPromo],
            historyStore: historyStore,
            triggerPublisher: triggerSubject.eraseToAnyPublisher(),
            stateQueue: testQueue,
            registrationFallbackTimeout: 0
        )
        let expectation = XCTestExpectation(description: "both promos visible")
        promoService.visiblePromosPublisher
            .sink { promos in
                let ids = Set(promos.map(\.id))
                if ids.contains("next-steps-cards") && ids.contains("remote-message-ntp") {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.newTabPageAppeared)
        await fulfillment(of: [expectation], timeout: timeout)
    }
}
