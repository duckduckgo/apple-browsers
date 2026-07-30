//
//  AccountInfoKeyFactoryTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

@testable import DDGSync

final class AccountInfoKeyFactoryTests: XCTestCase {

    private let accountSecretKey = Data(repeating: 0x01, count: 32)
    private let thirdPartyMainKey = Data(repeating: 0x02, count: 32)

    func testWhenThirdPartyMainKeyIsUnavailableThenCreatesRSA3072DefaultCredentialWrapper() throws {
        let crypter = CryptingMock()
        let factory = DefaultAccountInfoKeyFactory(crypter: crypter)

        let protectedKeys = try factory.makeProtectedKeys(accountSecretKey: accountSecretKey)

        let protectedKey = try XCTUnwrap(protectedKeys.first)
        XCTAssertEqual(protectedKeys.count, 1)
        XCTAssertEqual(protectedKey.encryptedWith, SyncCredentialID.defaultCredential)
        XCTAssertEqual(protectedKey.purpose, ProtectedKeyPurpose.accountInfo)
        XCTAssertEqual(try modulusByteCount(of: protectedKey), 384)
        XCTAssertFalse(try unwrapDefaultCredentialPrivateKey(protectedKey, crypter: crypter).isEmpty)
    }

    func testWhenThirdPartyMainKeyIsAvailableThenWrapsSameRSA3072PrivateKeyForBothCredentials() throws {
        let crypter = CryptingMock()
        let factory = DefaultAccountInfoKeyFactory(crypter: crypter)

        let protectedKeys = try factory.makeProtectedKeys(accountSecretKey: accountSecretKey,
                                                          thirdPartyMainKey: thirdPartyMainKey)

        let defaultCredentialKey = try XCTUnwrap(protectedKeys.first { $0.encryptedWith == SyncCredentialID.defaultCredential })
        let thirdPartyCredentialKey = try XCTUnwrap(protectedKeys.first { $0.encryptedWith == SyncCredentialID.thirdParty })
        XCTAssertEqual(protectedKeys.count, 2)
        XCTAssertEqual(defaultCredentialKey.kid, thirdPartyCredentialKey.kid)
        XCTAssertEqual(defaultCredentialKey.publicKey, thirdPartyCredentialKey.publicKey)
        XCTAssertEqual(defaultCredentialKey.purpose, ProtectedKeyPurpose.accountInfo)
        XCTAssertEqual(thirdPartyCredentialKey.purpose, ProtectedKeyPurpose.accountInfo)
        XCTAssertEqual(try modulusByteCount(of: defaultCredentialKey), 384)

        let defaultCredentialPrivateKey = try unwrapDefaultCredentialPrivateKey(defaultCredentialKey, crypter: crypter)
        let thirdPartyCredentialPrivateKey = try JWECompactCodec().decryptDirect(token: thirdPartyCredentialKey.encryptedPrivateKey,
                                                                                contentEncryptionKey: thirdPartyMainKey)
        XCTAssertEqual(defaultCredentialPrivateKey, thirdPartyCredentialPrivateKey)
    }

    private func modulusByteCount(of protectedKey: ProtectedKey) throws -> Int {
        let modulus = try XCTUnwrap(protectedKey.publicKey.n)
        return try XCTUnwrap(Base64URL.decode(modulus)).count
    }

    private func unwrapDefaultCredentialPrivateKey(_ protectedKey: ProtectedKey,
                                                   crypter: CryptingInternal) throws -> Data {
        let encryptedPrivateKey = try XCTUnwrap(Base64URL.decode(protectedKey.encryptedPrivateKey))
        return try crypter.decryptData(encryptedPrivateKey, using: accountSecretKey)
    }
}
