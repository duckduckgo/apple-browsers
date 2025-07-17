//
//  SaveCreditCardViewModelTests.swift
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
import BrowserServicesKit
import Core

final class SaveCreditCardViewModelTests: XCTestCase {
    
    private let vault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!
    private var viewModel: SaveCreditCardViewModel!
    let testGroupName = "test"
    var customSuite: UserDefaults!
    var testCard: SecureVaultModels.CreditCard!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        customSuite = UserDefaults(suiteName: testGroupName)
        customSuite.removePersistentDomain(forName: testGroupName)
        
        UserDefaults.app = customSuite
        
        testCard = createTestCreditCard()
        viewModel = SaveCreditCardViewModel(creditCard: testCard, accountDomain: "example.com", vault: vault)
    }
    
    override func tearDownWithError() throws {
        UserDefaults.app = .standard
        viewModel = nil
        vault.storedCards = []
        
        try super.tearDownWithError()
    }
    
    func testWhenCreditCardSavedThenCardIsSavedAndNoLongerFirstTimeUser() {
        viewModel.save()
        
        XCTAssertEqual(customSuite.bool(forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsFirstTimeUser.rawValue), false)
        XCTAssert(vault.storedCards.count == 1)
    }
    
    func testWhenCancelPromptThenRejectionCountIncrementedByOne() {
        customSuite.set(1, forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsSaveModalRejectionCount.rawValue)
        
        viewModel.cancelButtonPressed()
        
        XCTAssertEqual(customSuite.integer(forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsSaveModalRejectionCount.rawValue), 2)
    }
    
    func testWhenSameDomainThenRejectionCountNotIncrementedW() {
        // Given
        customSuite.set(1, forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsSaveModalRejectionCount.rawValue)
        viewModel = SaveCreditCardViewModel(creditCard: testCard, accountDomain: "example.com", domainLastShownOn: "example.com", vault: vault)
        
        // When
        viewModel.cancelButtonPressed()
        
        // Then
        XCTAssertEqual(customSuite.integer(forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsSaveModalRejectionCount.rawValue), 1)
    }
    
    func testWhenThresholdReachedThenDisablePromptShown() {
        // Given
        customSuite.set(1, forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsSaveModalRejectionCount.rawValue)
        
        // When
        viewModel.cancelButtonPressed()
        
        // Then
        XCTAssertTrue(customSuite.bool(forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsSaveModalDisablePromptShown.rawValue))
        XCTAssertFalse(customSuite.bool(forKey: UserDefaultsWrapper<Any>.Key.autofillCreditCardsFirstTimeUser.rawValue))
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
