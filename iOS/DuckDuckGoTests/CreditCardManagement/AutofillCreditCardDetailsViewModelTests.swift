//
//  AutofillCreditCardDetailsViewModelTests.swift
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

final class AutofillCreditCardDetailsViewModelTests: XCTestCase {
    
    private let vault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!
    private var viewModel: AutofillCreditCardDetailsViewModel!
    private var mockDelegate: MockAutofillCreditCardDetailsViewModelDelegate!
    private var mockAuthenticator: MockUserAuthenticator = MockUserAuthenticator(reason: "", cancelTitle: "")
    private var cancellables: Set<AnyCancellable> = []
    
    override func setUpWithError() throws {
        super.setUp()
        setupUserDefault(with: #file)
        mockDelegate = MockAutofillCreditCardDetailsViewModelDelegate()
        
        // Default setup with no credit card (new card mode)
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: nil
        )
        viewModel.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockDelegate = nil
        cancellables.removeAll()
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testInitInNewMode() {
        // When initialized without a credit card
        let viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: nil
        )
        
        // Then
        XCTAssertEqual(viewModel.viewMode, .new)
        XCTAssertEqual(viewModel.navigationTitle, UserText.autofillCreditCardDetailsNewTitle)
        XCTAssertEqual(viewModel.cardNumber, "")
        XCTAssertEqual(viewModel.formattedCardNumber, "")
        XCTAssertFalse(viewModel.isCardValid)
    }
    
    func testInitWithCreditCard() {
        // Given
        let card = createTestCreditCard()
        
        // When
        let viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        
        // Then
        XCTAssertEqual(viewModel.viewMode, .view)
        XCTAssertEqual(viewModel.cardNumber, card.cardNumber)
        XCTAssertEqual(viewModel.cardholderName, card.cardholderName)
        XCTAssertEqual(viewModel.cardTitle, card.title)
        XCTAssertEqual(viewModel.expirationMonth, card.expirationMonth)
        XCTAssertEqual(viewModel.expirationYear, card.expirationYear)
        XCTAssertEqual(viewModel.cardSecurityCode, card.cardSecurityCode ?? "")
    }
    
    // MARK: - Navigation Title Tests
    
    func testNavigationTitleInViewMode() {
        // Given
        let card = createTestCreditCard(title: "My Test Card")
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        
        // Then
        XCTAssertEqual(viewModel.navigationTitle, "My Test Card")
    }
    
    func testNavigationTitleInViewModeWithEmptyTitle() {
        // Given
        let card = createTestCreditCard(title: "", number: "4111111111111111") // Visa card
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        
        // Then - should use card type name
        XCTAssertEqual(viewModel.navigationTitle, "Visa")
    }
    
    func testNavigationTitleInEditMode() {
        // Given
        let card = createTestCreditCard()
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        
        // When
        viewModel.toggleEditMode()
        
        // Then
        XCTAssertEqual(viewModel.viewMode, .edit)
        XCTAssertEqual(viewModel.navigationTitle, UserText.autofillCreditCardDetailsEditTitle)
    }
    
    // MARK: - Toggle Edit Mode Tests
    
    func testToggleEditMode() {
        // Given
        let card = createTestCreditCard()
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        XCTAssertEqual(viewModel.viewMode, .view)
        
        // When - toggle to edit
        viewModel.toggleEditMode()
        
        // Then
        XCTAssertEqual(viewModel.viewMode, .edit)
        
        // When - toggle back to view
        viewModel.toggleEditMode()
        
        // Then
        XCTAssertEqual(viewModel.viewMode, .view)
    }
    
    func testToggleEditModeResetsSelectedCell() {
        // Given
        let card = createTestCreditCard()
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        let cellId = UUID()
        viewModel.selectedCell = cellId
        XCTAssertEqual(viewModel.selectedCell, cellId)
        
        // When
        viewModel.toggleEditMode()
        
        // Then
        XCTAssertNil(viewModel.selectedCell)
    }
    
    // MARK: - Copy to Clipboard Tests
    
    func testCopyCardNumberToPasteboard() {
        // Given
        viewModel.cardNumber = "4111111111111111"
        
        // When
        viewModel.copyToPasteboard(.cardNumber)
        
        // Then
        XCTAssertEqual(UIPasteboard.general.string, "4111111111111111")
    }
    
    func testCopyExpirationDateToPasteboard() {
        // Given
        let card = createTestCreditCard(month: 12, year: 2025)
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        
        // When
        viewModel.copyToPasteboard(.expirationDate)
        
        // Then
        XCTAssertEqual(UIPasteboard.general.string, viewModel.formattedExpiration)
    }
    
    func testCopyCardSecurityCodeToPasteboard() {
        // Given
        viewModel.cardSecurityCode = "123"
        
        // When
        viewModel.copyToPasteboard(.cardSecurityCode)
        
        // Then
        XCTAssertEqual(UIPasteboard.general.string, "123")
    }
    
    func testCopyCardholderNameToPasteboard() {
        // Given
        viewModel.cardholderName = "John Doe"
        
        // When
        viewModel.copyToPasteboard(.cardholderName)
        
        // Then
        XCTAssertEqual(UIPasteboard.general.string, "John Doe")
    }
    
    // MARK: - Save Credit Card Tests
    
    func testSaveNewCreditCard() {
        // Given
        vault.storedCards = []
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardholderName = "John Doe"
        viewModel.cardTitle = "My Visa Card"
        viewModel.expirationMonth = 12
        viewModel.expirationYear = 2030
        viewModel.cardSecurityCode = "123"
        viewModel.isCardValid = true // Set this to simulate valid card
        
        // Save initially empty
        XCTAssertTrue(vault.storedCards.isEmpty)
        
        // When
        viewModel.save()
        
        // Then
        XCTAssertFalse(vault.storedCards.isEmpty)
        XCTAssertEqual(vault.storedCards.count, 1)
        XCTAssertEqual(vault.storedCards[0].cardNumber, "4111111111111111")
        XCTAssertEqual(vault.storedCards[0].cardholderName, "John Doe")
        XCTAssertEqual(vault.storedCards[0].title, "My Visa Card")
        XCTAssertTrue(mockDelegate.didSaveCalled)
    }
    
    func testEditExistingCreditCard() {
        // Given
        let card = createTestCreditCard()
        vault.storedCards = [card]
        
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        viewModel.delegate = mockDelegate
        
        // Switch to edit mode
        viewModel.toggleEditMode()
        
        // Update card details
        viewModel.cardNumber = "5555555555554444" // Mastercard
        viewModel.cardholderName = "Jane Smith"
        viewModel.cardTitle = "Updated Card"
        viewModel.expirationMonth = 10
        viewModel.expirationYear = 2028
        viewModel.cardSecurityCode = "321"
        viewModel.isCardValid = true // Set this to simulate valid card
        
        // When
        viewModel.save()
        
        // Then
        XCTAssertEqual(vault.storedCards.count, 1)
        XCTAssertEqual(vault.storedCards[0].cardNumber, "5555555555554444")
        XCTAssertEqual(vault.storedCards[0].cardholderName, "Jane Smith")
        XCTAssertEqual(vault.storedCards[0].title, "Updated Card")
        XCTAssertTrue(mockDelegate.didSaveCalled)
        XCTAssertEqual(viewModel.viewMode, .view) // Should return to view mode
    }
    
    // MARK: - Delete Credit Card Test
    
    func testDeleteCreditCard() {
        // Given
        let card = createTestCreditCard()
        viewModel = AutofillCreditCardDetailsViewModel(
            authenticator: mockAuthenticator,
            secureVault: vault,
            creditCard: card
        )
        viewModel.delegate = mockDelegate
        
        // When
        viewModel.delete()
        
        // Then
        XCTAssertTrue(mockDelegate.didDeleteCalled)
        XCTAssertEqual(mockDelegate.deletedCard?.id, card.id)
    }
    
    // MARK: - Formatted Values Tests
    
    func testFormattedExpirationDate() {
        // Given
        viewModel.expirationMonth = 12
        viewModel.expirationYear = 2030
        
        // When
        let formatted = viewModel.expirationDateString()
        
        // Then
        XCTAssertEqual(formatted, "12 / 30")
    }
    
    func testMaskedSecurityCode() {
        // Given
        viewModel.cardSecurityCode = "123"
        viewModel.isSecurityCodeHidden = true
        
        // Then
        XCTAssertEqual(viewModel.userVisibleCardSecurityCode, "•••")
        
        // When
        viewModel.isSecurityCodeHidden = false
        
        // Then
        XCTAssertEqual(viewModel.userVisibleCardSecurityCode, "123")
    }
    
    // MARK: - Helper Methods
    
    private func createTestCreditCard(
        title: String = "Test Card",
        number: String = "4111111111111111",
        holderName: String = "Test User",
        month: Int = 12,
        year: Int = 2030,
        securityCode: String = "123"
    ) -> SecureVaultModels.CreditCard {
        return SecureVaultModels.CreditCard(
            id: Int64.random(in: 0..<Int64.max),
            title: title,
            cardNumber: number,
            cardholderName: holderName,
            cardSecurityCode: securityCode,
            expirationMonth: month,
            expirationYear: year)
    }
}

// MARK: - Mocks

private class MockUserAuthenticator: UserAuthenticator {
    var authenticateCalled = false
    var canAuthenticateValue = true
    
    override func authenticate(completion: ((AuthError?) -> Void)? = nil) {
        authenticateCalled = true
        completion?(nil)
    }
}

private class MockAutofillCreditCardDetailsViewModelDelegate: AutofillCreditCardDetailsViewModelDelegate {
    var didSaveCalled = false
    var didDeleteCalled = false
    var didDismissCalled = false
    var deletedCard: SecureVaultModels.CreditCard?
    
    func autofillCreditCardDetailsViewModelDidSave() {
        didSaveCalled = true
    }
    
    func autofillCreditCardDetailsViewModelDelete(card: SecureVaultModels.CreditCard) {
        didDeleteCalled = true
        deletedCard = card
    }
    
    func autofillCreditCardDetailsViewModelDismiss() {
        didDismissCalled = true
    }
}
