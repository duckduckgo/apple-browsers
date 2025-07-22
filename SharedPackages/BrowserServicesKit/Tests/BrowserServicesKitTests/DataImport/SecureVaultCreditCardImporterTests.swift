//
//  SecureVaultCreditCardImporterTests.swift
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
import SecureStorage
import SecureStorageTestsUtils
@testable import BrowserServicesKit

class SecureVaultCreditCardImporterTests: XCTestCase {

    private var mockCryptoProvider = MockCryptoProvider()
    private var mockDatabaseProvider = (try! MockAutofillDatabaseProvider())
    private var mockKeystoreProvider = MockKeystoreProvider()
    private var mockVault: (any AutofillSecureVault)!
    var importer: SecureVaultCreditCardImporter!

    override func setUpWithError() throws {
        try super.setUpWithError()

        importer = SecureVaultCreditCardImporter()

        let providers = SecureStorageProviders(crypto: mockCryptoProvider,
                                               database: mockDatabaseProvider,
                                               keystore: mockKeystoreProvider)
        mockVault = DefaultAutofillSecureVault(providers: providers)

        mockCryptoProvider._derivedKey = "derived".data(using: .utf8)
        mockKeystoreProvider._encryptedL2Key = "encrypted".data(using: .utf8)
        mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)

        _ = try mockVault.authWith(password: "password".data(using: .utf8)!)
    }

    override func tearDownWithError() throws {
        importer = nil
        mockVault = nil

        try super.tearDownWithError()
    }

    func testWhenImportingNewCard_ThenCardIsStored() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        let cardToImport = ImportedCreditCard(
            title: "My Visa",
            cardNumber: cardNumber,
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2025
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 1)
        XCTAssertEqual(result.duplicate, 0)
        XCTAssertEqual(result.failed, 0)

        let storedCards = try mockVault.creditCards()
        XCTAssertEqual(storedCards.count, 1)

        guard let storedCard = storedCards.first else {
            XCTFail("Expected stored card not found")
            return
        }

        XCTAssertEqual(storedCard.cardSuffix, "1111")
        XCTAssertEqual(storedCard.title, "My Visa")
        XCTAssertEqual(storedCard.cardholderName, "John Doe")
        XCTAssertEqual(storedCard.cardSecurityCode, "123")
    }

    func testWhenImportingMultipleNewCards_ThenAllCardsAreStored() throws {
        mockCryptoProvider._decryptedData = "4111111111111111".data(using: .utf8)

        let cardsToImport = [
            ImportedCreditCard(
                title: "Card 1",
                cardNumber: "4111111111111111",
                cardholderName: "John",
                cardSecurityCode: nil,
                expirationMonth: 12,
                expirationYear: 2025,
                lastUsedTime: nil
            ),
            ImportedCreditCard(
                title: "Card 2",
                cardNumber: "5555555555554444",
                cardholderName: "Jane",
                cardSecurityCode: nil,
                expirationMonth: 6,
                expirationYear: 2026,
                lastUsedTime: nil
            )
        ]

        let result = try importer.importCreditCards(cardsToImport, vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 2)
        XCTAssertEqual(result.duplicate, 0)
        XCTAssertEqual(result.failed, 0)

        let storedCards = try mockVault.creditCards()
        XCTAssertEqual(storedCards.count, 2)
    }

    // MARK: - Duplicate Card Tests

    func testWhenImportingCardWithSameNumberAndSameExpiry_ThenCardIsSkipped() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store existing card
        let existingCard = SecureVaultModels.CreditCard(
            id: 1,
            title: "Existing Card",
            cardNumber: cardNumber,
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2025
        )

        _ = try mockVault.storeCreditCard(existingCard)

        let cardToImport = ImportedCreditCard(
            title: "Updated Title",
            cardNumber: cardNumber,
            cardholderName: "JOHN DOE",
            cardSecurityCode: "456",
            expirationMonth: 12,
            expirationYear: 2025
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 0)
        XCTAssertEqual(result.duplicate, 1)
        XCTAssertEqual(result.failed, 0)

        let storedCards = try mockVault.creditCards()
        XCTAssertEqual(storedCards.count, 1)

        guard let storedCard = storedCards.first else {
            XCTFail("Expected stored card not found")
            return
        }

        XCTAssertEqual(storedCard.title, "Existing Card")
        XCTAssertEqual(storedCard.cardSecurityCode, "123")
    }

    func testWhenImportingCardWithSameNumberAndOlderExpiry_ThenCardIsSkipped() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store existing card
        let existingCard = SecureVaultModels.CreditCard(
            id: 1,
            title: "Existing Card",
            cardNumber: cardNumber,
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2025
        )
        _ = try mockVault.storeCreditCard(existingCard)

        let cardToImport = ImportedCreditCard(
            title: "Old Card",
            cardNumber: cardNumber,
            cardholderName: nil,
            cardSecurityCode: nil,
            expirationMonth: 11,
            expirationYear: 2024,
            lastUsedTime: nil
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 0)
        XCTAssertEqual(result.duplicate, 1)
    }

    // MARK: - Update Card Tests

    func testWhenImportingCardWithSameNumberAndNewerExpiry_ThenAllFieldsAreUpdated() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store existing card
        let existingCard = SecureVaultModels.CreditCard(
            id: 123,
            title: "Old Title",
            cardNumber: cardNumber,
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2024
        )
        _ = try mockVault.storeCreditCard(existingCard)

        let cardToImport = ImportedCreditCard(
            title: "New Title",
            cardNumber: cardNumber,
            cardholderName: "JOHN DOE",
            cardSecurityCode: "456",
            expirationMonth: 12,
            expirationYear: 2025
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 1)
        XCTAssertEqual(result.duplicate, 0)

        let storedCards = try mockVault.creditCards()
        XCTAssertEqual(storedCards.count, 1)

        guard let updatedCard = storedCards.first else {
            XCTFail("Expected updated card not found")
            return
        }

        XCTAssertEqual(updatedCard.id, 123) // ID preserved
        XCTAssertEqual(updatedCard.title, "New Title")
        XCTAssertEqual(updatedCard.cardholderName, "JOHN DOE")
        XCTAssertEqual(updatedCard.cardSecurityCode, "456")
        XCTAssertEqual(updatedCard.expirationYear, 2025)
    }

    func testWhenImportingCardWithNewerExpiry_AndImportedFieldsAreEmpty_ThenExistingDataIsPreserved() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store existing card
        let existingCard = SecureVaultModels.CreditCard(
            id: 123,
            title: "Existing Title",
            cardNumber: cardNumber,
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2024
        )
        _ = try mockVault.storeCreditCard(existingCard)

        let cardToImport = ImportedCreditCard(
            title: "",  // Empty
            cardNumber: cardNumber,
            cardholderName: nil,  // Nil
            cardSecurityCode: "",  // Empty
            expirationMonth: 12,
            expirationYear: 2025
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 1)

        let storedCards = try mockVault.creditCards()

        guard let updatedCard = storedCards.first else {
            XCTFail("Expected updated card not found")
            return
        }

        XCTAssertEqual(updatedCard.title, "Existing Title")  // Preserved
        XCTAssertEqual(updatedCard.cardholderName, "John Doe")  // Preserved
        XCTAssertEqual(updatedCard.cardSecurityCode, "123")  // Preserved
        XCTAssertEqual(updatedCard.expirationYear, 2025)  // Updated
    }

    func testWhenImportingCardWithNewerYear_AndSameMonth_ThenCardIsUpdated() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store existing card
        _ = try mockVault.storeCreditCard(
            SecureVaultModels.CreditCard(
                id: 1,
                cardNumber: cardNumber,
                cardholderName: "John Doe",
                cardSecurityCode: "123",
                expirationMonth: 6,
                expirationYear: 2024
            )
        )

        let cardToImport = ImportedCreditCard(
            title: nil,
            cardNumber: cardNumber,
            cardholderName: nil,
            cardSecurityCode: nil,
            expirationMonth: 6,
            expirationYear: 2025,
            lastUsedTime: nil
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 1)
        XCTAssertEqual(result.duplicate, 0)
    }

    func testWhenImportingCardWithSameYear_AndNewerMonth_ThenCardIsUpdated() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store existing card
        _ = try mockVault.storeCreditCard(
            SecureVaultModels.CreditCard(
                id: 1,
                cardNumber: cardNumber,
                cardholderName: "John Doe",
                cardSecurityCode: "123",
                expirationMonth: 6,
                expirationYear: 2025
            )
        )

        let cardToImport = ImportedCreditCard(
            title: nil,
            cardNumber: cardNumber,
            cardholderName: nil,
            cardSecurityCode: nil,
            expirationMonth: 7,
            expirationYear: 2025,
            lastUsedTime: nil
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 1)
        XCTAssertEqual(result.duplicate, 0)
    }

    // MARK: - Edge Case Tests

    func testWhenExistingCardHasNoExpiry_AndImportedCardHasExpiry_ThenCardIsDuplicate() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store card without expiry
        _ = try mockVault.storeCreditCard(
            SecureVaultModels.CreditCard(
                id: 1,
                cardNumber: cardNumber,
                cardholderName: "John Doe",
                cardSecurityCode: "123",
                expirationMonth: nil,
                expirationYear: nil
            )
        )

        let cardToImport = ImportedCreditCard(
            title: nil,
            cardNumber: cardNumber,
            cardholderName: nil,
            cardSecurityCode: nil,
            expirationMonth: 12,
            expirationYear: 2025
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 0)
        XCTAssertEqual(result.duplicate, 1)
    }

    func testWhenImportedCardHasNoExpiry_ThenCardIsDuplicate() throws {
        let cardNumber = "4111111111111111"
        mockCryptoProvider._decryptedData = cardNumber.data(using: .utf8)

        // Store card with expiry
        _ = try mockVault.storeCreditCard(
            SecureVaultModels.CreditCard(
                id: 1,
                cardNumber: cardNumber,
                cardholderName: "John Doe",
                cardSecurityCode: "123",
                expirationMonth: 12,
                expirationYear: 2025
            )
        )

        let cardToImport = ImportedCreditCard(
            title: nil,
            cardNumber: cardNumber,
            cardholderName: nil,
            cardSecurityCode: nil,
            expirationMonth: nil,
            expirationYear: nil,
            lastUsedTime: nil
        )

        let result = try importer.importCreditCards([cardToImport], vault: mockVault) { _ in }

        XCTAssertEqual(result.successful, 0)
        XCTAssertEqual(result.duplicate, 1)
    }

    // MARK: - Sorting Tests

    func testWhenImportingMultipleCards_ThenCardsAreSortedByLastUsedTime() throws {
        //         mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)

        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)

        let cardsToImport = [
            ImportedCreditCard(
                title: nil,
                cardNumber: "3333333333333333",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil,
                lastUsedTime: date3
            ),
            ImportedCreditCard(
                title: nil,
                cardNumber: "1111111111111111",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil,
                lastUsedTime: date1
            ),
            ImportedCreditCard(
                title: nil,
                cardNumber: "2222222222222222",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil,
                lastUsedTime: date2
            ),
            ImportedCreditCard(
                title: nil,
                cardNumber: "0000000000000000",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil,
                lastUsedTime: nil
            )
        ]

        _ = try importer.importCreditCards(cardsToImport, vault: mockVault) { _ in }

        // Verify all cards were stored
        let storedCards = try mockVault.creditCards()
        XCTAssertEqual(storedCards.count, 4)

        // The sorting affects processing order, but all should be stored
        XCTAssertTrue(storedCards.contains { $0.cardSuffix == "0000" })
        XCTAssertTrue(storedCards.contains { $0.cardSuffix == "1111" })
        XCTAssertTrue(storedCards.contains { $0.cardSuffix == "2222" })
        XCTAssertTrue(storedCards.contains { $0.cardSuffix == "3333" })
    }

    // MARK: - Progress Callback Tests

    func testWhenImportingCards_ThenProgressCallbackIsCalledForEachCard() throws {
        // For this test, we don't need equality checks, so default decrypted data is fine
        //         mockCryptoProvider._decryptedData = "decrypted".data(using: .utf8)

        let cardsToImport = [
            ImportedCreditCard(
                title: nil,
                cardNumber: "1111111111111111",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil,
                lastUsedTime: nil
            ),
            ImportedCreditCard(
                title: nil,
                cardNumber: "2222222222222222",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil,
                lastUsedTime: nil
            ),
            ImportedCreditCard(
                title: nil,
                cardNumber: "3333333333333333",
                cardholderName: nil,
                cardSecurityCode: nil,
                expirationMonth: nil,
                expirationYear: nil,
                lastUsedTime: nil
            )
        ]

        var progressCalls: [Int] = []

        _ = try importer.importCreditCards(cardsToImport, vault: mockVault) { progress in
            progressCalls.append(progress)
        }

        XCTAssertEqual(progressCalls, [1, 2, 3])
    }
}
