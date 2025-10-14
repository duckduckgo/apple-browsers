//
//  SyncableCreditCardsValidationTests.swift
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
import Common
import DDGSync
@testable import BrowserServicesKit
@testable import SyncDataProviders

final class SyncableCreditCardsValidationTests: XCTestCase {

    var syncableCreditCard: SecureVaultModels.SyncableCreditCard!

    override func setUp() {
        let creditCard = SecureVaultModels.CreditCard(
            id: 1,
            title: "Test Card",
            cardNumber: "4111111111111111",
            cardholderName: "John Doe",
            cardSecurityCode: "123",
            expirationMonth: 12,
            expirationYear: 2025
        )
        syncableCreditCard = SecureVaultModels.SyncableCreditCard(creditCard: creditCard, lastModified: nil)
    }

    func testWhenCreditCardFieldsPassLengthValidationThenSyncableIsInitializedWithoutThrowingErrors() throws {
        XCTAssertNoThrow(try Syncable(syncableCreditCard: syncableCreditCard, encryptedUsing: { $0 }))
    }

    func testWhenCardTitleIsTooLongThenSyncableInitializerThrowsError() throws {

        syncableCreditCard.creditCard?.title = String(repeating: "x", count: 3001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenCardholderNameIsTooLongThenSyncableInitializerThrowsError() throws {

        syncableCreditCard.creditCard?.cardholderName = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenCardNumberIsTooLongThenSyncableInitializerThrowsError() throws {

        let longCardNumber = String(repeating: "1", count: 501)
        let creditCard = SecureVaultModels.CreditCard(
            title: syncableCreditCard.creditCard?.title ?? "",
            cardNumber: longCardNumber,
            cardholderName: syncableCreditCard.creditCard?.cardholderName,
            cardSecurityCode: syncableCreditCard.creditCard?.cardSecurityCode,
            expirationMonth: syncableCreditCard.creditCard?.expirationMonth,
            expirationYear: syncableCreditCard.creditCard?.expirationYear
        )
        syncableCreditCard.creditCard = creditCard
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenCardSecurityCodeIsTooLongThenSyncableInitializerThrowsError() throws {

        syncableCreditCard.creditCard?.cardSecurityCode = String(repeating: "1", count: 101)
        assertSyncableInitializerThrowsValidationError()
    }

    func testValidCardNumberFormats() throws {
        let validCardNumbers = [
            "4111111111111111",
            "5555555555554444",
            "378282246310005",
            "6011111111111117",
            "3530111333300000"
        ]

        for cardNumber in validCardNumbers {
            let creditCard = SecureVaultModels.CreditCard(
                title: syncableCreditCard.creditCard?.title ?? "",
                cardNumber: cardNumber,
                cardholderName: syncableCreditCard.creditCard?.cardholderName,
                cardSecurityCode: syncableCreditCard.creditCard?.cardSecurityCode,
                expirationMonth: syncableCreditCard.creditCard?.expirationMonth,
                expirationYear: syncableCreditCard.creditCard?.expirationYear
            )
            syncableCreditCard.creditCard = creditCard
            XCTAssertNoThrow(try Syncable(syncableCreditCard: syncableCreditCard, encryptedUsing: { $0 }))
        }
    }

    func testValidSecurityCodeFormats() throws {
        let validCodes = ["123", "1234", "12", "9999", ""]

        for code in validCodes {
            syncableCreditCard.creditCard?.cardSecurityCode = code.isEmpty ? nil : code
            XCTAssertNoThrow(try Syncable(syncableCreditCard: syncableCreditCard, encryptedUsing: { $0 }))
        }
    }

    private func assertSyncableInitializerThrowsValidationError(file: StaticString = #file, line: UInt = #line) {
        XCTAssertThrowsError(
            try Syncable(syncableCreditCard: syncableCreditCard, encryptedUsing: { $0 }),
            file: file,
            line: line
        ) { error in
            guard case Syncable.SyncableCreditCardError.validationFailed = error else {
                XCTFail("unexpected error thrown: \(error)", file: file, line: line)
                return
            }
        }
    }
}
