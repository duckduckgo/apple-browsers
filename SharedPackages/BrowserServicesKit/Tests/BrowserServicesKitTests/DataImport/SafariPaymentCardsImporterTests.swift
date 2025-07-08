//
//  SafariPaymentCardsImporterTests.swift
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
@testable import BrowserServicesKit
import SecureStorage
import SecureStorageTestsUtils

#if os(iOS)
final class SafariPaymentCardsImporterTests: XCTestCase {

    private let temporaryFileCreator = TemporaryFileCreator()
    private var mockCryptoProvider = MockCryptoProvider()
    private var mockDatabaseProvider = (try! MockAutofillDatabaseProvider())
    private var mockKeystoreProvider = MockKeystoreProvider()
    private var mockCreditCardImporter: MockCreditCardImporter!
    private var mockVault: (any AutofillSecureVault)!

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockCreditCardImporter = MockCreditCardImporter()

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
        temporaryFileCreator.deleteCreatedTemporaryFiles()
        mockCreditCardImporter = nil
        mockVault = nil

        try super.tearDownWithError()
    }

    // MARK: - JSON Parsing Tests

    func testWhenImportingValidJSONContent_ThenCreditCardsAreExtracted() throws {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "4111111111111111",
                        "card_name": "Personal Visa",
                        "cardholder_name": "John Doe",
                        "card_expiration_month": 12,
                        "card_expiration_year": 2025,
                        "card_last_used_time_usec": 1703174400000000
                    }
                ]
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards[0].cardNumber, "4111111111111111")
        XCTAssertEqual(creditCards[0].title, "Personal Visa")
        XCTAssertEqual(creditCards[0].cardholderName, "John Doe")
        XCTAssertEqual(creditCards[0].expirationMonth, 12)
        XCTAssertEqual(creditCards[0].expirationYear, 2025)
        XCTAssertNil(creditCards[0].cardSecurityCode) // Safari doesn't export CVC
        XCTAssertNotNil(creditCards[0].lastUsedTime)
    }

    func testWhenImportingJSONWithMinimalFields_ThenCreditCardsAreExtracted() throws {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "5555555555554444"
                    }
                ]
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards[0].cardNumber, "5555555555554444")
        XCTAssertNil(creditCards[0].title)
        XCTAssertNil(creditCards[0].cardholderName)
        XCTAssertNil(creditCards[0].expirationMonth)
        XCTAssertNil(creditCards[0].expirationYear)
        XCTAssertNil(creditCards[0].lastUsedTime)
    }

    func testWhenImportingJSONWithNullValues_ThenNilsAreHandledGracefully() throws {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "4111111111111111",
                        "card_name": null,
                        "cardholder_name": null,
                        "card_expiration_month": null,
                        "card_expiration_year": null,
                        "card_last_used_time_usec": null
                    }
                ]
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 1)
        XCTAssertEqual(creditCards[0].cardNumber, "4111111111111111")
        XCTAssertNil(creditCards[0].title)
        XCTAssertNil(creditCards[0].cardholderName)
        XCTAssertNil(creditCards[0].expirationMonth)
        XCTAssertNil(creditCards[0].expirationYear)
        XCTAssertNil(creditCards[0].lastUsedTime)
    }

    func testWhenImportingJSONWithMultipleCards_ThenAllCardsAreExtracted() throws {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "4111111111111111",
                        "card_name": "Visa",
                        "cardholder_name": "John Doe"
                    },
                    {
                        "card_number": "5555555555554444",
                        "card_name": "MasterCard",
                        "cardholder_name": "Jane Smith"
                    },
                    {
                        "card_number": "378282246310005",
                        "card_name": "Amex",
                        "cardholder_name": "Bob Johnson"
                    }
                ]
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 3)
        XCTAssertEqual(creditCards[0].cardNumber, "4111111111111111")
        XCTAssertEqual(creditCards[1].cardNumber, "5555555555554444")
        XCTAssertEqual(creditCards[2].cardNumber, "378282246310005")
    }

    func testWhenImportingEmptyPaymentCardsArray_ThenNoCardsAreExtracted() throws {
        let jsonContent = """
            {
                "payment_cards": []
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 0)
    }

    func testWhenImportingCardsWithSpecialCharacters_ThenCardsAreImportedAsIs() throws {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "4111-1111-1111-1111",
                        "cardholder_name": "John O'Doe"
                    },
                    {
                        "card_number": "4111 1111 1111 1111",
                        "cardholder_name": "María García"
                    }
                ]
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 2)
        XCTAssertEqual(creditCards[0].cardNumber, "4111-1111-1111-1111")
        XCTAssertEqual(creditCards[1].cardNumber, "4111 1111 1111 1111")
        XCTAssertEqual(creditCards[0].cardholderName, "John O'Doe")
        XCTAssertEqual(creditCards[1].cardholderName, "María García")
    }

    // MARK: - Error Handling Tests

    func testWhenImportingInvalidJSON_ThenErrorIsThrown() {
        let invalidJSON = "{ invalid json"

        XCTAssertThrowsError(try SafariPaymentCardsImporter.extractCreditCards(from: invalidJSON)) { error in
            XCTAssertNotNil(error)
        }
    }

    func testWhenImportingJSONWithoutPaymentCardsKey_ThenErrorIsThrown() {
        let jsonContent = """
            {
                "other_data": []
            }
            """

        XCTAssertThrowsError(try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)) { error in
            XCTAssertNotNil(error)
        }
    }

    func testWhenImportingMalformedJSON_ThenErrorIsThrown() {
        let jsonContent = """
            {
                "payment_cards": "not_an_array"
            }
            """

        XCTAssertThrowsError(try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)) { error in
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Date Conversion Tests

    func testWhenLastUsedTimeInMicroseconds_ThenCorrectDateIsCreated() throws {
        let microseconds: Double = 1703174400000000 // 2023-12-21 16:00:00 UTC
        let expectedDate = Date(timeIntervalSince1970: 1703174400) // Same time in seconds

        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "4111111111111111",
                        "card_last_used_time_usec": \(microseconds)
                    }
                ]
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 1)
        XCTAssertNotNil(creditCards[0].lastUsedTime)
        let lastUsedTime = try XCTUnwrap(creditCards[0].lastUsedTime)
        XCTAssertEqual(lastUsedTime.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Expiration Date Tests

    func testWhenExpirationDatesAreValid_ThenTheyAreImportedCorrectly() throws {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "4111111111111111",
                        "card_expiration_month": 1,
                        "card_expiration_year": 2025
                    },
                    {
                        "card_number": "5555555555554444",
                        "card_expiration_month": 12,
                        "card_expiration_year": 2030
                    }
                ]
            }
            """

        let creditCards = try SafariPaymentCardsImporter.extractCreditCards(from: jsonContent)

        XCTAssertEqual(creditCards.count, 2)
        XCTAssertEqual(creditCards[0].expirationMonth, 1)
        XCTAssertEqual(creditCards[0].expirationYear, 2025)
        XCTAssertEqual(creditCards[1].expirationMonth, 12)
        XCTAssertEqual(creditCards[1].expirationYear, 2030)
    }

    // MARK: - File Import Tests

    func testWhenImportingFromValidFile_ThenCreditCardsAreImported() async {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "4111111111111111",
                        "cardholder_name": "John Doe"
                    }
                ]
            }
            """

        let savedFileURL = temporaryFileCreator.persist(fileContents: jsonContent.data(using: .utf8)!, named: "cards.json")!
        let importer = SafariPaymentCardsImporter(fileURL: savedFileURL, creditCardImporter: mockCreditCardImporter, vault: mockVault)

        mockCreditCardImporter.expectedSummary = DataImport.DataTypeSummary(successful: 1, duplicate: 0, failed: 0)

        let result = await importer.importData(types: [.creditCards]).task.value

        XCTAssertEqual(result, [.creditCards: .success(.init(successful: 1, duplicate: 0, failed: 0))])
        XCTAssertTrue(mockCreditCardImporter.importCalled)
        XCTAssertEqual(mockCreditCardImporter.importedCards?.count, 1)
    }

    func testWhenImportingFromJSONContent_ThenCreditCardsAreImported() async {
        let jsonContent = """
            {
                "payment_cards": [
                    {
                        "card_number": "5555555555554444",
                        "cardholder_name": "Jane Smith"
                    }
                ]
            }
            """

        let importer = SafariPaymentCardsImporter(fileURL: nil, jsonContent: jsonContent, creditCardImporter: mockCreditCardImporter, vault: mockVault)

        mockCreditCardImporter.expectedSummary = DataImport.DataTypeSummary(successful: 1, duplicate: 0, failed: 0)

        let result = await importer.importData(types: [.creditCards]).task.value

        XCTAssertEqual(result, [.creditCards: .success(.init(successful: 1, duplicate: 0, failed: 0))])
        XCTAssertTrue(mockCreditCardImporter.importCalled)
        XCTAssertEqual(mockCreditCardImporter.importedCards?.count, 1)
    }

    func testWhenImportingWithNoFileOrContent_ThenErrorIsReturned() async {
        let importer = SafariPaymentCardsImporter(fileURL: nil, jsonContent: nil, creditCardImporter: mockCreditCardImporter, vault: mockVault)

        let result = await importer.importData(types: [.creditCards]).task.value

        guard case .failure(let error) = result[.creditCards] else {
            XCTFail("Expected failure result")
            return
        }

        XCTAssertNotNil(error)
    }

    // MARK: - Static Methods Tests

    func testWhenCountingValidCreditCardsFromFile_ThenCorrectCountIsReturned() {
        let jsonContent = """
            {
                "payment_cards": [
                    {"card_number": "4111111111111111"},
                    {"card_number": "5555555555554444"},
                    {"card_number": "378282246310005"}
                ]
            }
            """

        let savedFileURL = temporaryFileCreator.persist(fileContents: jsonContent.data(using: .utf8)!, named: "cards.json")!

        let count = SafariPaymentCardsImporter.totalValidCreditCards(in: savedFileURL)

        XCTAssertEqual(count, 3)
    }

    func testWhenCountingValidCreditCardsFromString_ThenCorrectCountIsReturned() {
        let jsonContent = """
            {
                "payment_cards": [
                    {"card_number": "4111111111111111"},
                    {"card_number": "5555555555554444"}
                ]
            }
            """

        let count = SafariPaymentCardsImporter.totalValidCreditCards(in: jsonContent)

        XCTAssertEqual(count, 2)
    }

    func testWhenCountingValidCreditCardsFromInvalidJSON_ThenZeroIsReturned() {
        let invalidJSON = "invalid json"

        let count = SafariPaymentCardsImporter.totalValidCreditCards(in: invalidJSON)

        XCTAssertEqual(count, 0)
    }

    func testWhenCountingValidCreditCardsFromEmptyArray_ThenZeroIsReturned() {
        let jsonContent = """
            {
                "payment_cards": []
            }
            """

        let count = SafariPaymentCardsImporter.totalValidCreditCards(in: jsonContent)

        XCTAssertEqual(count, 0)
    }

    // MARK: - Progress Callback Tests

    func testWhenImportingCreditCards_ThenProgressCallbacksAreInvoked() async {
        let jsonContent = """
            {
                "payment_cards": [
                    {"card_number": "4111111111111111"},
                    {"card_number": "5555555555554444"}
                ]
            }
            """

        let importer = SafariPaymentCardsImporter(fileURL: nil, jsonContent: jsonContent, creditCardImporter: mockCreditCardImporter, vault: mockVault)

        mockCreditCardImporter.expectedSummary = DataImport.DataTypeSummary(successful: 2, duplicate: 0, failed: 0)

        let result = await importer.importData(types: [.creditCards]).task.value

        XCTAssertEqual(result, [.creditCards: .success(.init(successful: 2, duplicate: 0, failed: 0))])
    }

    // MARK: - Vault Tests

    func testWhenImportingCreditCards_ThenVaultIsPassedToImporter() async {
        let jsonContent = """
            {
                "payment_cards": [
                    {"card_number": "4111111111111111"}
                ]
            }
            """

        let importer = SafariPaymentCardsImporter(fileURL: nil, jsonContent: jsonContent, creditCardImporter: mockCreditCardImporter, vault: mockVault)

        mockCreditCardImporter.expectedSummary = DataImport.DataTypeSummary(successful: 1, duplicate: 0, failed: 0)

        _ = await importer.importData(types: [.creditCards]).task.value

        XCTAssertTrue(mockCreditCardImporter.vaultWasPassed)
        XCTAssertNotNil(mockCreditCardImporter.passedVault)
    }

    // MARK: - Importable Types Tests

    func testWhenCheckingImportableTypes_ThenOnlyCreditCardsIsReturned() {
        let importer = SafariPaymentCardsImporter(fileURL: nil, jsonContent: nil, creditCardImporter: mockCreditCardImporter, vault: mockVault)

        let importableTypes = importer.importableTypes

        XCTAssertEqual(importableTypes, [.creditCards])
    }

    // MARK: - Cancellation Tests

    func testWhenImportIsCancelled_ThenImportStopsGracefully() async {
        let jsonContent = """
            {
                "payment_cards": [
                    {"card_number": "4111111111111111"},
                    {"card_number": "5555555555554444"}
                ]
            }
            """

        let importer = SafariPaymentCardsImporter(fileURL: nil, jsonContent: jsonContent, creditCardImporter: mockCreditCardImporter, vault: mockVault)

        mockCreditCardImporter.shouldThrowCancellationError = true

        let result = await importer.importData(types: [.creditCards]).task.value

        XCTAssertTrue(result.isEmpty)
    }
}

private class MockCreditCardImporter: CreditCardImporter {
    var importCalled = false
    var importedCards: [ImportedCreditCard]?
    var expectedSummary = DataImport.DataTypeSummary(successful: 0, duplicate: 0, failed: 0)
    var shouldThrowCancellationError = false
    var vaultWasPassed = false
    var passedVault: (any AutofillSecureVault)?

    func importCreditCards(_ cards: [ImportedCreditCard], vault: (any AutofillSecureVault)?, completion: @escaping (Int) throws -> Void) throws -> DataImport.DataTypeSummary {
        importCalled = true
        importedCards = cards
        passedVault = vault
        vaultWasPassed = vault != nil

        if shouldThrowCancellationError {
            throw CancellationError()
        }

        return expectedSummary
    }
}
#endif
