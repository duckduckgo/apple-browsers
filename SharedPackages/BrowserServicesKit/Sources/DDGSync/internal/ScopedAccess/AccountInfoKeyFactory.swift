//
//  AccountInfoKeyFactory.swift
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

import Foundation

protocol AccountInfoKeyFactory {
    func makeProtectedKeys(accountSecretKey: Data, thirdPartyMainKey: Data?) throws -> [ProtectedKey]
}

struct DefaultAccountInfoKeyFactory: AccountInfoKeyFactory {

    private static let keySizeInBits = 3072

    private let crypter: CryptingInternal
    private let jweCompactCodec: JWECompactCodec

    init(crypter: CryptingInternal, jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.crypter = crypter
        self.jweCompactCodec = jweCompactCodec
    }

    /// Creates one RSA key pair and wraps its private key for each available account credential.
    func makeProtectedKeys(accountSecretKey: Data, thirdPartyMainKey: Data? = nil) throws -> [ProtectedKey] {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial(keySizeInBits: Self.keySizeInBits)
        let keyID = UUID().uuidString
        let defaultCredentialKey = try makeDefaultCredentialKey(keyMaterial: keyMaterial,
                                                                keyID: keyID,
                                                                accountSecretKey: accountSecretKey)
        guard let thirdPartyMainKey else {
            return [defaultCredentialKey]
        }

        let thirdPartyCredentialKey = try makeThirdPartyCredentialKey(keyMaterial: keyMaterial,
                                                                      keyID: keyID,
                                                                      thirdPartyMainKey: thirdPartyMainKey)
        return [defaultCredentialKey, thirdPartyCredentialKey]
    }

    private func makeDefaultCredentialKey(keyMaterial: ScopedAccessKeyFactory.RSAKeyMaterial,
                                          keyID: String,
                                          accountSecretKey: Data) throws -> ProtectedKey {
        let encryptedPrivateKey = try crypter.encrypt(keyMaterial.privateKeyPKCS8, using: accountSecretKey)
        return ProtectedKey(kid: keyID,
                            encryptedPrivateKey: Base64URL.encode(encryptedPrivateKey),
                            publicKey: keyMaterial.publicKeyJWK,
                            encryptedWith: SyncCredentialID.defaultCredential,
                            purpose: ProtectedKeyPurpose.accountInfo)
    }

    private func makeThirdPartyCredentialKey(keyMaterial: ScopedAccessKeyFactory.RSAKeyMaterial,
                                             keyID: String,
                                             thirdPartyMainKey: Data) throws -> ProtectedKey {
        let encryptedPrivateKey = try jweCompactCodec.encryptDirect(payload: keyMaterial.privateKeyPKCS8,
                                                                    contentEncryptionKey: thirdPartyMainKey,
                                                                    kid: SyncCredentialID.thirdParty)
        return ProtectedKey(kid: keyID,
                            encryptedPrivateKey: encryptedPrivateKey,
                            publicKey: keyMaterial.publicKeyJWK,
                            encryptedWith: SyncCredentialID.thirdParty,
                            purpose: ProtectedKeyPurpose.accountInfo)
    }
}
