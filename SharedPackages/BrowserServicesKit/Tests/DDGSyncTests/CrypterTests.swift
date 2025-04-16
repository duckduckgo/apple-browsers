//
//  CrypterTests.swift
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

import Clibsodium
import CryptoKit
import XCTest
import DDGSyncCrypto
@testable import DDGSync

class CrypterTests: XCTestCase {

    func testWhenGivenRecoveryKeyThenCanExtractSecretKey() throws {
        let storage = SecureStorageStub()
        let crypter = Crypter(secureStore: storage)

        let userId = "Simple User Name"

        let account = try crypter.createAccountCreationKeys(userId: userId, password: "password")
        let recoveryKey = SyncCode.RecoveryKey(userId: userId, primaryKey: account.primaryKey)
        let login = try crypter.extractLoginInfo(recoveryKey: recoveryKey)
        XCTAssertEqual(account.passwordHash, login.passwordHash)

        // The login flow calls the server to retreve the protected secret key, but we already have it so check we can decrypt it.

        let secretKey = try crypter.extractSecretKey(protectedSecretKey: account.protectedSecretKey, stretchedPrimaryKey: login.stretchedPrimaryKey)
        XCTAssertEqual(account.secretKey, secretKey)
    }

    func testWhenGivenRecoveryKeyThenCanExtractUserIdAndPrimaryKey() throws {
        let storage = SecureStorageStub()
        let crypter = Crypter(secureStore: storage)

        let userId = "Simple User Name"
        let primaryKey = Data([UInt8](repeating: 1, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue)))

        let recoveryKey = SyncCode.RecoveryKey(userId: userId, primaryKey: primaryKey)
        let loginInfo = try crypter.extractLoginInfo(recoveryKey: recoveryKey)

        XCTAssertEqual(loginInfo.userId, userId)
        XCTAssertEqual(loginInfo.primaryKey, primaryKey)
    }

    func testWhenDecryptingNoneBase64ThenErrorIsThrown() throws {
        let storage = SecureStorageStub()
        let primaryKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        let secretKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        try storage.persistAccount(SyncAccount(deviceId: "deviceId",
                                               deviceName: "deviceName",
                                               deviceType: "deviceType",
                                               userId: "userId",
                                               primaryKey: primaryKey,
                                               secretKey: secretKey,
                                               token: "token",
                                               state: .active))
        let message = "😆 " + UUID().uuidString + " 🥴 " + UUID().uuidString

        let crypter = Crypter(secureStore: storage)

        XCTAssertThrowsError(try crypter.base64DecodeAndDecrypt(message))
    }

    func testWhenDecryptingGarbageBase64DataThenErrorIsThrown() throws {
        let storage = SecureStorageStub()
        let primaryKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        let secretKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        try storage.persistAccount(SyncAccount(deviceId: "deviceId",
                                               deviceName: "deviceName",
                                               deviceType: "deviceType",
                                               userId: "userId",
                                               primaryKey: primaryKey,
                                               secretKey: secretKey,
                                               token: "token",
                                               state: .active))
        let randomMessage = SymmetricKey(size: .bits256).withUnsafeBytes { Data(Array($0)).base64EncodedString() }

        let crypter = Crypter(secureStore: storage)

        XCTAssertThrowsError(try crypter.base64DecodeAndDecrypt(randomMessage))
    }

    func testWhenEncryptingValueThenItIsBase64AndCanBeDecrypted() throws {
        let storage = SecureStorageStub()
        let primaryKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        let secretKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        try storage.persistAccount(SyncAccount(deviceId: "deviceId",
                                               deviceName: "deviceName",
                                               deviceType: "deviceType",
                                               userId: "userId",
                                               primaryKey: primaryKey,
                                               secretKey: secretKey,
                                               token: "token",
                                               state: .active))
        let message = "😆 " + UUID().uuidString + " 🥴 " + UUID().uuidString

        let crypter = Crypter(secureStore: storage)
        let encrypted = try crypter.encryptAndBase64Encode(message)
        XCTAssertNotEqual(encrypted, message)
        assertValidBase64(encrypted)

        let decrypted = try crypter.base64DecodeAndDecrypt(encrypted)
        XCTAssertEqual(decrypted, message)
    }

    func testWhenDecryptingEmptyStringThenEmptyStringIsReturned() throws {
        let storage = SecureStorageStub()
        let primaryKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        let secretKey = Data([UInt8]((0 ..< DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue).map { _ in UInt8.random(in: 0 ..< UInt8.max )}))
        try storage.persistAccount(SyncAccount(deviceId: "deviceId",
                                               deviceName: "deviceName",
                                               deviceType: "deviceType",
                                               userId: "userId",
                                               primaryKey: primaryKey,
                                               secretKey: secretKey,
                                               token: "token",
                                               state: .active))
        let message = ""
        let crypter = Crypter(secureStore: storage)

        XCTAssertEqual(try crypter.base64DecodeAndDecrypt(message), "")
    }

    func assertValidBase64(_ base64: String) {
        for c in base64 {
            XCTAssertTrue(c.isLetter || c.isNumber || ["+", "/", "="].contains(c), "\(c) not valid base64 char")
        }
    }

}
