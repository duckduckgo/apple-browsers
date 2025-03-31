//
//  SecureStorageCryptoProviderTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import SecureStorage

private class TestCryptoProvider: SecureStorageCryptoProvider {

    var passwordSalt: Data { return Data() }
    var hashingSalt: Data? { return _hashingSalt }
    var keychainServiceName: String { return "service" }
    var keychainAccountName: String { return "account" }

    var _hashingSalt: Data?
}

final class SecureStorageCryptoProviderTests: XCTestCase {

    func testWhenEncryptingData_AndTheKeyIsCorrect_ThenItCanBeDecrypted() throws {
        let provider = TestCryptoProvider()
        let key = try provider.generateSecretKey()

        let secretData = "Hello, world!".data(using: .utf8)!

        let encryptedData = try provider.encrypt(secretData, withKey: key)
        XCTAssertNotEqual(secretData, encryptedData)

        let decryptedData = try provider.decrypt(encryptedData, withKey: key)
        XCTAssertNotEqual(decryptedData, encryptedData)
        XCTAssertEqual(decryptedData, secretData)

        XCTAssertEqual(String(data: decryptedData, encoding: .utf8)!, "Hello, world!")
    }

    func testWhenHashingData_NoSaltIsGiven_ThenNoHashIsReturned() throws {
        let provider = TestCryptoProvider()
        let dataToHash = "Hello, world!".data(using: .utf8)!

        XCTAssertNil(try provider.hashData(dataToHash))
    }

    func testWhenHashingData_AndDifferentSaltsAreGiven_ThenTheResultsAreDifferent() throws {
        let provider = TestCryptoProvider()
        provider._hashingSalt = try provider.generateSecretKey()

        let dataToHash = "Hello, world!".data(using: .utf8)!

        let firstHashedData = try provider.hashData(dataToHash)
        XCTAssertEqual(try provider.hashData(dataToHash), firstHashedData) // Verify that the hash is the same when the key hasn't changed

        provider._hashingSalt = try provider.generateSecretKey()
        let secondHashedData = try provider.hashData(dataToHash)

        XCTAssertNotEqual(firstHashedData, secondHashedData)
    }

}
