//
//  AutofillCreditCardListViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Core
import BrowserServicesKit
import Combine

final class AutofillCreditCardListViewModelTests: XCTestCase {
    
    private var mockViewModel: MockCreditCardListViewModel!
    
    override func setUpWithError() throws {
        super.setUp()
        
        mockViewModel = MockCreditCardListViewModel()
    }
    
    override func tearDownWithError() throws {
        mockViewModel = nil

        try super.tearDownWithError()
    }

    // MARK: - Authentication Tests

    func testAuthenticateWhenAuthNotAvailable() {
        // Given
        mockViewModel.setViewState(.noAuthAvailable)
        mockViewModel.simulateAuthenticationNotAvailable()

        var completionError: UserAuthenticator.AuthError?
        let expectation = self.expectation(description: "Authentication completion called")

        // When
        mockViewModel.authenticate { error in
            completionError = error
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(completionError, .noAuthAvailable)
        XCTAssertEqual(mockViewModel.viewState, .noAuthAvailable)
        XCTAssertTrue(mockViewModel.authenticateCalled)
    }

    func testAuthenticateSuccess() {
        // Given
        mockViewModel.setViewState(.authLocked)

        var completionCalled = false
        let expectation = self.expectation(description: "Authentication completion called")

        // When
        mockViewModel.authenticate { _ in
            completionCalled = true
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(completionCalled)
        XCTAssertEqual(mockViewModel.viewState, .empty) // Empty because no cards
        XCTAssertTrue(mockViewModel.authenticateCalled)
    }

    func testAuthenticateWithCards() {
        // Given
        mockViewModel.setViewState(.authLocked)
        mockViewModel.populateCards(count: 2)

        var completionCalled = false
        let expectation = self.expectation(description: "Authentication completion called")

        // When
        mockViewModel.authenticate { _ in
            completionCalled = true
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(completionCalled)
        XCTAssertEqual(mockViewModel.viewState, .showItems)
        XCTAssertTrue(mockViewModel.authenticateCalled)
    }

    func testAuthenticateFailure() {
        // Given
        mockViewModel.setViewState(.authLocked)
        mockViewModel.simulateAuthenticationFailure(error: .failedToAuthenticate)

        var receivedError: UserAuthenticator.AuthError?
        let expectation = self.expectation(description: "Authentication failure called")

        // When
        mockViewModel.authenticate { error in
            receivedError = error
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertNotNil(receivedError)
        XCTAssertEqual(receivedError, .failedToAuthenticate)
        XCTAssertEqual(mockViewModel.viewState, .authLocked)
        XCTAssertTrue(mockViewModel.authenticateCalled)
    }

    func testLockUI() {
        // Given
        mockViewModel.populateCards(count: 2)
        mockViewModel.setViewState(.showItems)

        // When
        mockViewModel.lockUI()

        // Then
        XCTAssertTrue(mockViewModel.lockUICalled)
        XCTAssertFalse(mockViewModel.authenticationNotRequired) // Because there are cards
        XCTAssertEqual(mockViewModel.viewState, .authLocked)
    }

    func testLockUIWithNoCards() {
        // Given
        mockViewModel.cards = [] // No cards
        mockViewModel.setViewState(.showItems)

        // When
        mockViewModel.lockUI()

        // Then
        XCTAssertTrue(mockViewModel.lockUICalled)
        XCTAssertTrue(mockViewModel.authenticationNotRequired) // Because there are no cards
        XCTAssertEqual(mockViewModel.viewState, .empty)
    }

    func testCardSelected() {
        // Given
        mockViewModel.populateCards(count: 1)
        let cardViewModel = mockViewModel.cards[0]

        // When
        mockViewModel.cardSelected(cardViewModel)

        // Then
        XCTAssertTrue(mockViewModel.cardSelectedCalled)
        XCTAssertEqual(mockViewModel.lastSelectedCard, cardViewModel)
    }

    func testDeleteCard() {
        // Given
        mockViewModel.populateCards(count: 2)
        let cardToDelete = mockViewModel.cards[0].creditCard
        let initialCount = mockViewModel.cards.count

        // When
        mockViewModel.deleteCard(cardToDelete)

        // Then
        XCTAssertTrue(mockViewModel.deleteCardCalled)
        XCTAssertEqual(mockViewModel.lastDeletedCard?.id, cardToDelete.id)
        XCTAssertEqual(mockViewModel.cards.count, initialCount - 1)
    }
}

class MockCreditCardListViewModel: CreditCardListViewModelProtocol {
    var objectWillChange = ObservableObjectPublisher()
    
    var cards: [CreditCardRowViewModel] = [] {
        didSet { objectWillChange.send() }
    }
    private(set) var viewState: AutofillCreditCardListViewModel.ViewState = .authLocked {
        didSet { objectWillChange.send() }
    }
    var authenticationNotRequired: Bool = false {
        didSet { objectWillChange.send() }
    }
    var hasCardsSaved: Bool {
        return !cards.isEmpty
    }
    
    // Testing properties
    var authenticateCalled = false
    var lockUICalled = false
    var refreshDataCalled = false
    var deleteCardCalled = false
    var cardSelectedCalled = false
    
    var lastSelectedCard: CreditCardRowViewModel?
    var lastDeletedCard: SecureVaultModels.CreditCard?
    var simulatedAuthError: UserAuthenticator.AuthError?
    
    func cardSelected(_ cardViewModel: CreditCardRowViewModel) {
        cardSelectedCalled = true
        lastSelectedCard = cardViewModel
    }
    
    func refreshData() {
        refreshDataCalled = true
    }
    
    func deleteCard(_ creditCard: SecureVaultModels.CreditCard) {
        deleteCardCalled = true
        lastDeletedCard = creditCard
        // Remove from cards if present
        cards.removeAll { $0.creditCard.title == creditCard.title }
    }
    
    func lockUI() {
        lockUICalled = true
        authenticationNotRequired = !hasCardsSaved
        viewState = authenticationNotRequired ? .empty : .authLocked
    }
    
    func authenticate(completion: @escaping (UserAuthenticator.AuthError?) -> Void) {
        authenticateCalled = true
        
        if let error = simulatedAuthError {
            completion(error)
        } else {
            viewState = cards.count > 0 ? .showItems : .empty
            completion(nil)
        }
    }
    
    // Helper methods for testing
    func simulateAuthenticationSuccess() {
        simulatedAuthError = nil
        viewState = cards.count > 0 ? .showItems : .empty
    }
    
    func simulateAuthenticationFailure(error: UserAuthenticator.AuthError = .failedToAuthenticate) {
        simulatedAuthError = error
        viewState = .authLocked
    }
    
    func simulateAuthenticationNotAvailable() {
        simulatedAuthError = .noAuthAvailable
        viewState = .noAuthAvailable
    }
    
    func setViewState(_ state: AutofillCreditCardListViewModel.ViewState) {
        viewState = state
    }
    
    func populateCards(count: Int) {
        for i in 0..<count {
            let card = SecureVaultModels.CreditCard(
                title: "Test Card \(i)",
                cardNumber: "4111111111111111",
                cardholderName: "Test User",
                cardSecurityCode: "123",
                expirationMonth: 12,
                expirationYear: 2030
            )
            cards.append(CreditCardRowViewModel(creditCard: card))
        }
    }
}
