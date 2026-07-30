//
//  DeviceInfoCodecTests.swift
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

final class DeviceInfoCodecTests: XCTestCase {

    private let accountSecretKey = Data(repeating: 0x01, count: 32)

    func testWhenEncryptingDeviceInfoWithRSA3072ProtectedKeyThenRoundTripSucceeds() throws {
        let crypter = CryptingMock()
        let protectedKey = try XCTUnwrap(
            DefaultAccountInfoKeyFactory(crypter: crypter)
                .makeProtectedKeys(accountSecretKey: accountSecretKey)
                .first
        )
        let keyMaterial = try makeKeyMaterial(from: protectedKey, crypter: crypter)
        let deviceInfo = DeviceInfo(name: "Anya's Mac", type: "desktop")
        let codec = DeviceInfoCodec()

        let encryptedDeviceInfo = try codec.encrypt(deviceInfo, using: protectedKey)
        let decryptedDeviceInfo = try codec.decrypt(encryptedDeviceInfo, using: keyMaterial)

        XCTAssertEqual(decryptedDeviceInfo, deviceInfo)
    }

    func testWhenEncryptingWithProtectedKeyForDifferentPurposeThenThrows() throws {
        let crypter = CryptingMock()
        let accountInfoKey = try XCTUnwrap(
            DefaultAccountInfoKeyFactory(crypter: crypter)
                .makeProtectedKeys(accountSecretKey: accountSecretKey)
                .first
        )
        let protectedKey = ProtectedKey(kid: accountInfoKey.kid,
                                        encryptedPrivateKey: accountInfoKey.encryptedPrivateKey,
                                        publicKey: accountInfoKey.publicKey,
                                        encryptedWith: accountInfoKey.encryptedWith,
                                        purpose: "ai_chats")

        XCTAssertThrowsError(try DeviceInfoCodec().encrypt(DeviceInfo(name: "iPhone", type: "mobile"),
                                                           using: protectedKey)) { error in
            XCTAssertEqual(error as? DeviceInfoCodecError, .invalidProtectedKey)
        }
    }

    func testWhenDecryptedPayloadIsNotDeviceInfoThenThrows() throws {
        let keyPair = try RSAKeyPairGenerator.makeKeyPair()
        let keyMaterial = AccountInfoKeyMaterial(kid: "account-info-key",
                                                 publicKey: keyPair.publicKey,
                                                 privateKey: keyPair.privateKey)
        let encryptedPayload = try JWECompactCodec().encryptRSAOAEP256(payload: Data("invalid".utf8),
                                                                      recipientPublicKey: keyPair.publicKey,
                                                                      kid: keyMaterial.kid)

        XCTAssertThrowsError(try DeviceInfoCodec().decrypt(encryptedPayload, using: keyMaterial)) { error in
            XCTAssertEqual(error as? DeviceInfoCodecError, .invalidPayload)
        }
    }

    private func makeKeyMaterial(from protectedKey: ProtectedKey,
                                 crypter: CryptingInternal) throws -> AccountInfoKeyMaterial {
        let encryptedPrivateKey = try XCTUnwrap(Base64URL.decode(protectedKey.encryptedPrivateKey))
        let privateKeyPKCS8 = try crypter.decryptData(encryptedPrivateKey, using: accountSecretKey)
        return AccountInfoKeyMaterial(kid: protectedKey.kid,
                                      publicKey: try RSAKeyImporter.makePublicKey(from: protectedKey.publicKey),
                                      privateKey: try RSAKeyImporter.makePrivateKey(fromPKCS8: privateKeyPKCS8))
    }
}
