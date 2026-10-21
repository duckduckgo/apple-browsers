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
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        cardsSubject = CurrentValueSubject([])
        mockCardsProvider = MockNextStepsCardsProvider(cardsSubject: cardsSubject)
    }

    override func tearDown() {
        cardsSubject = nil
        mockCardsProvider = nil
        cancellables.removeAll()
        super.tearDown()
    }

    private func makeProvider(with cards: [NewTabPageDataModel.CardID]) {
        cardsSubject = CurrentValueSubject<[NewTabPageDataModel.CardID], Never>(cards)
        mockCardsProvider = MockNextStepsCardsProvider(cardsSubject: cardsSubject)
    }

    func testWhenCardsEmpty_ThenIsVisibleIsFalse() {
        let delegate = NextStepsCardsPromoDelegate(cardsProvider: mockCardsProvider)

        XCTAssertFalse(delegate.isVisible)
    }

    func testWhenCardsNonEmpty_ThenIsVisibleIsTrue() {
        makeProvider(with: [.defaultApp])
        let delegate = NextStepsCardsPromoDelegate(cardsProvider: mockCardsProvider)

        XCTAssertTrue(delegate.isVisible)
    }

    func testWhenCardsEmpty_ThenIsVisiblePublisherEmitsFalse() {
        let delegate = NextStepsCardsPromoDelegate(cardsProvider: mockCardsProvider)
        let exp = XCTestExpectation(description: "visibility")
        var receivedValue: Bool?
        delegate.isVisiblePublisher
            .sink { visible in
                receivedValue = visible
                exp.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(try XCTUnwrap(receivedValue))
    }

    func testWhenCardsNonEmpty_ThenIsVisiblePublisherEmitsTrue() {
        makeProvider(with: [.defaultApp])
        let delegate = NextStepsCardsPromoDelegate(cardsProvider: mockCardsProvider)
        let exp = XCTestExpectation(description: "visibility")
        var receivedValue: Bool?
        delegate.isVisiblePublisher
            .sink { visible in
                receivedValue = visible
                exp.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(try XCTUnwrap(receivedValue))
    }

    func testWhenCardsChangeFromNonEmptyToEmpty_ThenVisibilityUpdates() {
        makeProvider(with: [.defaultApp])
        let delegate = NextStepsCardsPromoDelegate(cardsProvider: mockCardsProvider)
        let exp = XCTestExpectation(description: "visibility drops")
        var receivedValue: Bool?
        delegate.isVisiblePublisher
            .dropFirst()
            .sink { visible in
                receivedValue = visible
                if !visible {
                    exp.fulfill()
                }
            }
            .store(in: &cancellables)

        cardsSubject.send([])
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(try XCTUnwrap(receivedValue))
    }

    func testResultWhenHidden_IsIgnoredPermanent() {
        let delegate = NextStepsCardsPromoDelegate(cardsProvider: mockCardsProvider)

        if case .ignored(cooldown: nil) = delegate.resultWhenHidden {
            // Expected: permanent dismiss
        } else {
            XCTFail("Expected resultWhenHidden to be .ignored() (cooldown: nil)")
        }
    }
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
