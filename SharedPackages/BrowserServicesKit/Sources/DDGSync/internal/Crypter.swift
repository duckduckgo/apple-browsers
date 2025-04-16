//
//  Crypter.swift
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

import Foundation
import DDGSyncCrypto

struct Crypter: CryptingInternal {

    let secureStore: SecureStoring

    func fetchSecretKey() throws -> Data {
        guard let account = try secureStore.account() else {
            throw SyncError.accountNotFound
        }
        return account.secretKey
    }

    func encryptAndBase64Encode(_ value: String) throws -> String {
        try encryptAndBase64Encode(value, using: try fetchSecretKey())
    }

    func base64DecodeAndDecrypt(_ value: String) throws -> String {
        try base64DecodeAndDecrypt(value, using: try fetchSecretKey())
    }

    func encryptAndBase64Encode(_ value: String, using secretKey: Data) throws -> String {
        var encryptionKey: [UInt8] = secretKey.safeBytes
        var rawBytes = Array(value.utf8)
        var encryptedBytes = [UInt8](repeating: 0, count: rawBytes.count + Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))
        assert(encryptionKey.count == Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue) ||
               encryptionKey.count == Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        let result = ddgSyncEncrypt(&encryptedBytes, &rawBytes, UInt64(rawBytes.count), &encryptionKey)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToEncryptValue("ddgSyncEncrypt failed: \(result)")
        }

        return Data(encryptedBytes).base64EncodedString()
    }

    func base64DecodeAndDecrypt(_ value: String, using secretKey: Data) throws -> String {
        guard !value.isEmpty else { return "" }
        var decryptionKey: [UInt8] = secretKey.safeBytes
        guard let data = Data(base64Encoded: value) else {
            throw SyncError.failedToDecryptValue("Unable to decode base64 value")
        }
        assert(decryptionKey.count == Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue) ||
               decryptionKey.count == Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        guard data.count >= Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue) else {
            throw SyncError.failedToDecryptValue("ddgSyncDecrypt failed: invalid ciphertext length: \(data.count)")
        }
        var encryptedBytes = data.safeBytes
        var rawBytes = [UInt8](repeating: 0, count: encryptedBytes.count - Int(DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE.rawValue))

        let result = ddgSyncDecrypt(&rawBytes, &encryptedBytes, UInt64(encryptedBytes.count), &decryptionKey)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToDecryptValue("ddgSyncDecrypt failed: \(result)")
        }

        guard let decryptedValue = String(data: Data(rawBytes), encoding: .utf8) else {
            throw SyncError.failedToDecryptValue("bytes could not be converted to string")
        }

        return decryptedValue
    }

    func createAccountCreationKeys(userId: String, password: String) throws -> AccountCreationKeys {

        var primaryKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue))
        var secretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var protectedSecretKey = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PROTECTED_SECRET_KEY_SIZE.rawValue))
        var passwordHash = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))

        let result = ddgSyncGenerateAccountKeys(&primaryKey, &secretKey, &protectedSecretKey, &passwordHash, userId, password)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToCreateAccountKeys("ddgSyncGenerateAccountKeys() failed: \(result)")
        }

        return AccountCreationKeys(
            primaryKey: Data(primaryKey),
            secretKey: Data(secretKey),
            protectedSecretKey: Data(protectedSecretKey),
            passwordHash: Data(passwordHash)
        )
    }

    func extractLoginInfo(recoveryKey: SyncCode.RecoveryKey) throws -> ExtractedLoginInfo {
        let primaryKeySize = Int(DDGSYNCCRYPTO_PRIMARY_KEY_SIZE.rawValue)

        var primaryKeyBytes = [UInt8](repeating: 0, count: primaryKeySize)
        var passwordHashBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_HASH_SIZE.rawValue))
        var strechedPrimaryKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE.rawValue))

        assert(recoveryKey.primaryKey.count == primaryKeySize)

        primaryKeyBytes = recoveryKey.primaryKey.safeBytes

        let result = ddgSyncPrepareForLogin(&passwordHashBytes, &strechedPrimaryKeyBytes, &primaryKeyBytes)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToCreateAccountKeys("ddgSyncPrepareForLogin failed: \(result)")
        }

        return ExtractedLoginInfo(
            userId: recoveryKey.userId,
            primaryKey: Data(primaryKeyBytes),
            passwordHash: Data(passwordHashBytes),
            stretchedPrimaryKey: Data(strechedPrimaryKeyBytes)
        )

    }

    func extractSecretKey(protectedSecretKey: Data, stretchedPrimaryKey: Data) throws -> Data {
        var secretKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        var protectedSecretKeyBytes = protectedSecretKey.safeBytes
        assert(protectedSecretKey.count == Int(DDGSYNCCRYPTO_PROTECTED_SECRET_KEY_SIZE.rawValue))

        var stretchedPrimaryKeyBytes = stretchedPrimaryKey.safeBytes
        assert(stretchedPrimaryKeyBytes.count == Int(DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE.rawValue))

        let result = ddgSyncDecrypt(&secretKeyBytes, &protectedSecretKeyBytes, UInt64(protectedSecretKeyBytes.count), &stretchedPrimaryKeyBytes)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToCreateAccountKeys("ddgSyncDecrypt failed: \(result)")
        }

        return Data(secretKeyBytes)
    }

    func prepareForConnect() throws -> ConnectInfo {
        var publicKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PUBLIC_KEY_SIZE.rawValue))
        var secretKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIVATE_KEY_SIZE.rawValue))
        let result = ddgSyncPrepareForConnect(&publicKeyBytes, &secretKeyBytes)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToPrepareForConnect("ddgSyncPrepareForConnect failed: \(result)")
        }
        return ConnectInfo(deviceID: UUID().uuidString,
                           publicKey: Data(publicKeyBytes),
                           secretKey: Data(secretKeyBytes))
    }

    func prepareForExchange() throws -> ExchangeInfo {
        var publicKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PUBLIC_KEY_SIZE.rawValue))
        var secretKeyBytes = [UInt8](repeating: 0, count: Int(DDGSYNCCRYPTO_PRIVATE_KEY_SIZE.rawValue))
        let result = ddgSyncPrepareForConnect(&publicKeyBytes, &secretKeyBytes)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToPrepareForExchange("ddgSyncPrepareForExchange failed: \(result)")
        }
        return ExchangeInfo(keyId: UUID().uuidString,
                            publicKey: Data(publicKeyBytes),
                            secretKey: Data(secretKeyBytes))
    }

    func seal(_ data: Data, secretKey: Data) throws -> Data {
        var rawBytes = data.safeBytes
        var secretKeyBytes = secretKey.safeBytes
        var encryptedBytes = [UInt8](repeating: 0, count: rawBytes.count + Int(DDGSYNCCRYPTO_SEAL_EXTRA_BYTES_SIZE.rawValue))
        assert(secretKey.count == Int(DDGSYNCCRYPTO_SECRET_KEY_SIZE.rawValue))
        let result = ddgSyncSeal(&encryptedBytes, &secretKeyBytes, &rawBytes, UInt64(rawBytes.count))
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToSealData("ddgSyncSeal failed: \(result)")
        }
        return Data(encryptedBytes)
    }

    func unseal(encryptedData: Data, publicKey: Data, secretKey: Data) throws -> Data {
        var encryptedBytes = encryptedData.safeBytes
        var rawBytes = [UInt8](repeating: 0, count: encryptedBytes.count - Int(DDGSYNCCRYPTO_SEAL_EXTRA_BYTES_SIZE.rawValue))
        assert(publicKey.count == Int(DDGSYNCCRYPTO_PUBLIC_KEY_SIZE.rawValue))
        assert(secretKey.count == Int(DDGSYNCCRYPTO_PRIVATE_KEY_SIZE.rawValue))
        var publicKeyBytes = publicKey.safeBytes
        var secretKeyBytes = secretKey.safeBytes

        let result = ddgSyncSealOpen(&encryptedBytes, UInt64(encryptedBytes.count), &publicKeyBytes, &secretKeyBytes, &rawBytes)
        guard DDGSYNCCRYPTO_OK == result else {
            throw SyncError.failedToOpenSealedBox("ddgSyncSealOpen failed: \(result)")
        }
        return Data(rawBytes)
    }

}

extension Data {

    var safeBytes: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        copyBytes(to: &bytes, from: 0 ..< count)
        return bytes
    }

}
