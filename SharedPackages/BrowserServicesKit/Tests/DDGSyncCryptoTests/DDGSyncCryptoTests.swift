//
//  DDGSyncCryptoTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import DDGSyncCrypto
import Clibsodium

class DDGSyncCryptoTests: XCTestCase {

    var primaryKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
    var secretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
    var protectedSecretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PROTECTED_SECRET_KEY_SIZE.rawValue))
    var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))

    func testWhenEncryptingDataThenOutputCanBeDecryptedValid() {

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                   &secretKey,
                                                                  &protectedSecretKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        let message = "🍻" + UUID().uuidString + "↘️" + UUID().uuidString + "😱"

        var encryptedBytes = [UInt8](repeating: 0, count: message.utf8.count + Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))
        var rawBytes = Array(message.utf8)

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncEncrypt(&encryptedBytes, &rawBytes, UInt64(rawBytes.count), &secretKey))
        assertValidKey(encryptedBytes)

        var decryptedBytes = [UInt8](repeating: 0, count: encryptedBytes.count - Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncDecrypt(&decryptedBytes, &encryptedBytes, UInt64(encryptedBytes.count), &secretKey))
        XCTAssertEqual(String(data: Data(decryptedBytes), encoding: .utf8), message)

    }

    func testWhenGeneratingAccountKeysThenEachKeyIsValid() {

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                  &secretKey,
                                                                  &protectedSecretKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        assertValidKey(primaryKey)
        assertValidKey(secretKey)
        assertValidKey(protectedSecretKey)
        assertValidKey(passwordHash)
    }

    func testWhenGeneratingAccountKeysThenPrimaryIsDeterministic() {
        var primaryKey2 = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                  &secretKey,
                                                                  &protectedSecretKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey2,
                                                                  &secretKey,
                                                                  &protectedSecretKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        assertValidKey(primaryKey)
        assertValidKey(primaryKey2)

        XCTAssertEqual(primaryKey, primaryKey2)
    }

    func testWhenGeneratingAccountKeysThenSecretKeyIsNonDeterministic() {
        var secretKey2 = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                  &secretKey,
                                                                  &protectedSecretKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        XCTAssertEqual(DDGSYNCCRYPTO_OK, ddgSyncGenerateAccountKeys(&primaryKey,
                                                                  &secretKey2,
                                                                  &protectedSecretKey,
                                                                  &passwordHash,
                                                                  "UserID",
                                                                  "Password"))

        // The chance of these being randomly the same is so low that it should never happen.
        XCTAssertNotEqual(secretKey, secretKey2)
    }

    func assertValidKey(_ key: [UInt8]) {
        var nullCount = 0
        for value in key where value == 0 {
            nullCount += 1
        }
        XCTAssertNotEqual(nullCount, key.count)
    }

}
