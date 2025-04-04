//
//  CreditCardValidationTests.swift
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

final class CreditCardValidationTests: XCTestCase {

    // MARK: - Card Type Detection Tests

    func testCardTypeDetection() {
        // Test Visa detection
        XCTAssertEqual(CreditCardValidation.type(for: "4111111111111111"), .visa)
        XCTAssertEqual(CreditCardValidation.type(for: "4012888888881881"), .visa)
        XCTAssertEqual(CreditCardValidation.type(for: "4222222222222"), .visa)

        // Test Mastercard detection
        XCTAssertEqual(CreditCardValidation.type(for: "5555555555554444"), .mastercard)
        XCTAssertEqual(CreditCardValidation.type(for: "5105105105105100"), .mastercard)
        XCTAssertEqual(CreditCardValidation.type(for: "2221000000000000"), .mastercard) // New BIN range
        XCTAssertEqual(CreditCardValidation.type(for: "2720990000000000"), .mastercard) // New BIN range

        // Test American Express detection
        XCTAssertEqual(CreditCardValidation.type(for: "378282246310005"), .amex)
        XCTAssertEqual(CreditCardValidation.type(for: "371449635398431"), .amex)
        XCTAssertEqual(CreditCardValidation.type(for: "340000000000000"), .amex)

        // Test Discover detection
        XCTAssertEqual(CreditCardValidation.type(for: "6011111111111117"), .discover)
        XCTAssertEqual(CreditCardValidation.type(for: "6011000990139424"), .discover)
        XCTAssertEqual(CreditCardValidation.type(for: "6511000000000000"), .discover)

        // Test Diners Club detection
        XCTAssertEqual(CreditCardValidation.type(for: "30569309025904"), .dinersClub)
        XCTAssertEqual(CreditCardValidation.type(for: "38520000023237"), .dinersClub)

        // Test JCB detection
        XCTAssertEqual(CreditCardValidation.type(for: "3530111333300000"), .jcb)
        XCTAssertEqual(CreditCardValidation.type(for: "3566002020360505"), .jcb)

        // Test Union Pay detection
        XCTAssertEqual(CreditCardValidation.type(for: "6212345678901232"), .unionPay)
        XCTAssertEqual(CreditCardValidation.type(for: "6250941006528599"), .unionPay)

        // Test unknown card type
        XCTAssertEqual(CreditCardValidation.type(for: "9999999999999999"), .unknown)
        XCTAssertEqual(CreditCardValidation.type(for: "1234567890123456"), .unknown)
    }

    func testCardTypeDisplayNames() {
        XCTAssertEqual(CreditCardValidation.CardType.visa.displayName, "Visa")
        XCTAssertEqual(CreditCardValidation.CardType.mastercard.displayName, "MasterCard")
        XCTAssertEqual(CreditCardValidation.CardType.amex.displayName, "American Express")
        XCTAssertEqual(CreditCardValidation.CardType.discover.displayName, "Discover")
        XCTAssertEqual(CreditCardValidation.CardType.dinersClub.displayName, "Diner's Club")
        XCTAssertEqual(CreditCardValidation.CardType.jcb.displayName, "JCB")
        XCTAssertEqual(CreditCardValidation.CardType.unionPay.displayName, "Union Pay")
        XCTAssertEqual(CreditCardValidation.CardType.unknown.displayName, "Card")
    }

    // MARK: - Card Number Formatting Tests

    func testFormattedCardNumber() {
        // Test standard 16-digit card formatting (grouped in 4s)
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("4111111111111111"), "4111 1111 1111 1111")
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("5555555555554444"), "5555 5555 5555 4444")

        // Test American Express format (4-6-5)
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("378282246310005"), "3782 822463 10005")
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("371449635398431"), "3714 496353 98431")

        // Test incomplete card numbers
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("411111"), "4111 11")
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("3782"), "3782")
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("37828224"), "3782 8224")

        // Test with spaces and other characters already in the input
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("4111 1111 1111 1111"), "4111 1111 1111 1111")
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("4111-1111-1111-1111"), "4111 1111 1111 1111")
        XCTAssertEqual(CreditCardValidation.formattedCardNumber("4111.1111.1111.1111"), "4111 1111 1111 1111")

        // Test empty string
        XCTAssertEqual(CreditCardValidation.formattedCardNumber(""), "")
    }

    func testExtractDigits() {
        XCTAssertEqual(CreditCardValidation.extractDigits(from: "4111 1111 1111 1111"), "4111111111111111")
        XCTAssertEqual(CreditCardValidation.extractDigits(from: "3782 822463 10005"), "378282246310005")
        XCTAssertEqual(CreditCardValidation.extractDigits(from: "4111-1111-1111-1111"), "4111111111111111")
        XCTAssertEqual(CreditCardValidation.extractDigits(from: "Card: 4111.1111.1111.1111"), "4111111111111111")
        XCTAssertEqual(CreditCardValidation.extractDigits(from: "Not a card number"), "")
    }

    // MARK: - Card Validation Tests

    func testCardNumberValidation() {
        // Valid card numbers (passing Luhn check and length requirements)
        XCTAssertTrue(CreditCardValidation.isValidCardNumber("4111111111111111")) // Visa
        XCTAssertTrue(CreditCardValidation.isValidCardNumber("5555555555554444")) // Mastercard
        XCTAssertTrue(CreditCardValidation.isValidCardNumber("378282246310005")) // Amex
        XCTAssertTrue(CreditCardValidation.isValidCardNumber("6011111111111117")) // Discover
        XCTAssertTrue(CreditCardValidation.isValidCardNumber("30569309025904")) // Diners Club
        XCTAssertTrue(CreditCardValidation.isValidCardNumber("3530111333300000")) // JCB

        // Invalid - fail Luhn check
        XCTAssertFalse(CreditCardValidation.isValidCardNumber("4111111111111112"))
        XCTAssertFalse(CreditCardValidation.isValidCardNumber("5555555555554443"))

        // Invalid - too short
        XCTAssertFalse(CreditCardValidation.isValidCardNumber("41111"))
        XCTAssertFalse(CreditCardValidation.isValidCardNumber("1234567"))

        // Invalid - too long
        XCTAssertFalse(CreditCardValidation.isValidCardNumber("41111111111111111111")) // 20 digits

        // Invalid - non-numeric characters (should be stripped before validation)
        XCTAssertFalse(CreditCardValidation.isValidCardNumber("4111-1111-1111-1111"))
        XCTAssertFalse(CreditCardValidation.isValidCardNumber("4111 1111 1111 1111"))
    }
}
