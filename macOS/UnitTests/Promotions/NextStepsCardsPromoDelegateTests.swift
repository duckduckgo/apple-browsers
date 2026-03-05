//
//  NextStepsCardsPromoDelegateTests.swift
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

final class NextStepsCardsPromoDelegateTests: XCTestCase {

    private var cardsSubject: CurrentValueSubject<[NewTabPageDataModel.CardID], Never>!
    private var mockCardsProvider: MockNextStepsCardsProvider!
    private var appearancePreferences: AppearancePreferences!
    private var delegate: NextStepsCardsPromoDelegate!

    override func setUp() {
        super.setUp()
        cardsSubject = CurrentValueSubject([])
        mockCardsProvider = MockNextStepsCardsProvider(cardsSubject: cardsSubject)
        appearancePreferences = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(continueSetUpCardsClosed: false),
            privacyConfigurationManager: nil,
            featureFlagger: nil,
            aiChatMenuConfig: MockAIChatConfig()
        )
        delegate = NextStepsCardsPromoDelegate(
            cardsProvider: mockCardsProvider,
            appearancePreferences: appearancePreferences,
            promoService: nil
        )
    }

    override func tearDown() {
        cardsSubject = nil
        mockCardsProvider = nil
        appearancePreferences = nil
        delegate = nil
        super.tearDown()
    }

    func testWhenCardsEmpty_ThenIsEligibleIsFalse() {
        cardsSubject.send([])
        delegate.refreshEligibility()
        XCTAssertFalse(delegate.isEligible)
    }

    func testWhenCardsNonEmpty_ThenIsEligibleIsTrue() {
        cardsSubject.send([.defaultApp])
        delegate.refreshEligibility()
        XCTAssertTrue(delegate.isEligible)
    }

    func testWhenCardsChangeFromNonEmptyToEmpty_ThenEligibilityUpdates() {
        cardsSubject.send([.defaultApp])
        delegate.refreshEligibility()
        XCTAssertTrue(delegate.isEligible)

        cardsSubject.send([])
        let exp = XCTestExpectation(description: "eligibility drops")
        delegate.isEligiblePublisher
            .dropFirst()
            .sink { eligible in
                if !eligible { exp.fulfill() }
            }
            .store(in: &cancellables)
        wait(for: [exp], timeout: 1.0)
        XCTAssertFalse(delegate.isEligible)
    }

    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Mock

private final class MockNextStepsCardsProvider: NewTabPageNextStepsCardsProviding {
    private let cardsSubject: CurrentValueSubject<[NewTabPageDataModel.CardID], Never>

    var cards: [NewTabPageDataModel.CardID] { cardsSubject.value }
    var cardsPublisher: AnyPublisher<[NewTabPageDataModel.CardID], Never> { cardsSubject.eraseToAnyPublisher() }

    var isViewExpanded: Bool = false
    var isViewExpandedPublisher: AnyPublisher<Bool, Never> { Just(isViewExpanded).eraseToAnyPublisher() }

    init(cardsSubject: CurrentValueSubject<[NewTabPageDataModel.CardID], Never>) {
        self.cardsSubject = cardsSubject
    }

    @MainActor
    func handleAction(for card: NewTabPageDataModel.CardID) {}
    @MainActor
    func dismiss(_ card: NewTabPageDataModel.CardID) {}
    @MainActor
    func willDisplayCards(_ cards: [NewTabPageDataModel.CardID]) {}
}
