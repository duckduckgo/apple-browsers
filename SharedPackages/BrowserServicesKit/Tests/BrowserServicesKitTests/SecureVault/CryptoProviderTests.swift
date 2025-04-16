//
//  CryptoProviderTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation

import XCTest
import CryptoKit
@testable import BrowserServicesKit
import SecureStorage

class CryptoProviderTests: XCTestCase {

    func testWhenDecryptingWithKeyFromInvalidPassword_ThenThrowsInvalidPasswordError() throws {

        let provider = AutofillCryptoProvider()

        let example = "example"
        let exampleData = example.data(using: .utf8)!

        let password = "password"
        let passwordData = password.data(using: .utf8)!

        let derivedKey = try provider.deriveKeyFromPassword(passwordData)
        let encrypted = try provider.encrypt(exampleData, withKey: derivedKey)

        let wrongPasswordKey = try provider.deriveKeyFromPassword("wrong".data(using: .utf8)!)
        do {
            _ = try provider.decrypt(encrypted, withKey: wrongPasswordKey)
            XCTFail("Expected throws")
        } catch {
            if case SecureStorageError.invalidPassword = error {
                // We good
            } else {
                XCTFail("Expected invalidPassword, received \(error)")
            }
        }

    }

    func testWhenDataEncryptedWithKey_ThenItCanBeDecryptedWithKey() throws {

        let provider = AutofillCryptoProvider()

        let example = "password"
        let exampleData = example.data(using: .utf8)!

        let key = try provider.generateSecretKey()

        let encrypted = try provider.encrypt(exampleData, withKey: key)
        XCTAssertNotEqual(encrypted, exampleData)

        let decrypted = try provider.decrypt(encrypted, withKey: key)
        XCTAssertEqual(decrypted, exampleData)

    }

    func testWhenGeneratingASecretKey_ThenKeyHasRequiredLengthAndNonNilData() throws {
        let provider = AutofillCryptoProvider()
        let key = try provider.generateSecretKey()
        XCTAssertGreaterThanOrEqual(key.count, 32)
        XCTAssertGreaterThan(key.filter { $0 > 0 }.count, 0)
    }

    func testWhenDerivingAKeyFromAPassword_ThenKeyHasRequiredLengthAndNonNilData() throws {
        let provider = AutofillCryptoProvider()
        let key = try provider.deriveKeyFromPassword("password".data(using: .utf8)!)
        XCTAssertGreaterThanOrEqual(key.count, 32)
        XCTAssertGreaterThan(key.filter { $0 > 0 }.count, 0)
    }

    func testWhenGeneratingPassword_ThenPasswordHasRequiredLengthAndNonNilData() throws {
        let provider = AutofillCryptoProvider()
        let password = try provider.generatePassword()
        XCTAssertGreaterThanOrEqual(password.count, 32)
        XCTAssertGreaterThan(password.filter { $0 > 0 }.count, 0)
    }

}
