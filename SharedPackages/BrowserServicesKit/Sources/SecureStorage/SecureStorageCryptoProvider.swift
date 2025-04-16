//
//  SecureStorageCryptoProvider.swift
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
import CommonCrypto
import CryptoKit

public protocol SecureStorageCryptoProvider {

    func generateSecretKey() throws -> Data

    func generatePassword() throws -> Data

    func deriveKeyFromPassword(_ password: Data) throws -> Data

    func encrypt(_ data: Data, withKey key: Data) throws -> Data

    func decrypt(_ data: Data, withKey key: Data) throws -> Data

    func hashData(_ data: Data) throws -> String?

    func hashData(_ data: Data, salt: Data?) throws -> String?

    var passwordSalt: Data { get }

    var hashingSalt: Data? { get }

    var keychainServiceName: String { get }

    var keychainAccountName: String { get }

}

// MARK: - SecureStorageCryptoProvider Default Implementation

private enum SecureStorageCryptoProviderConstants {
    public static let keySizeInBytes = 256 / 8
}

public extension SecureStorageCryptoProvider {

    func generateSecretKey() throws -> Data {
        return SymmetricKey(size: .bits256).dataRepresentation
    }

    func generatePassword() throws -> Data {
        var data = Data(count: SecureStorageCryptoProviderConstants.keySizeInBytes)
        let result = data.withUnsafeMutableBytes {
            return SecRandomCopyBytes(kSecRandomDefault, SecureStorageCryptoProviderConstants.keySizeInBytes, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw SecureStorageError.secError(status: result)
        }
        return data
    }

    func deriveKeyFromPassword(_ password: Data) throws -> Data {
        let salt = self.passwordSalt
        var key = Data(repeating: 0, count: SecureStorageCryptoProviderConstants.keySizeInBytes)
        let keyLength = key.count
        let status: OSStatus = key.withUnsafeMutableBytes { derivedKeyBytes in
            let derivedKeyRawBytes = derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress
            return salt.withUnsafeBytes { saltBytes in
                let rawSaltBytes = saltBytes.bindMemory(to: UInt8.self).baseAddress
                return password.withUnsafeBytes { passwordBytes in
                    let rawPasswordBytes = passwordBytes.bindMemory(to: Int8.self).baseAddress
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        rawPasswordBytes,
                        password.count,
                        rawSaltBytes,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(1024),
                        derivedKeyRawBytes,
                        keyLength)
                }
            }
        }

        guard status == kCCSuccess else {
            throw SecureStorageError.secError(status: status)
        }

        return key
    }

    func encrypt(_ data: Data, withKey key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedData = try AES.GCM.seal(data, using: symmetricKey)
        guard let data = sealedData.combined else {
            throw SecureStorageError.generalCryptoError
        }
        return data
    }

    func decrypt(_ data: Data, withKey key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        do {
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            if case CryptoKitError.authenticationFailure = error {
                throw SecureStorageError.invalidPassword
            } else {
                throw error
            }
        }
    }

    func hashData(_ data: Data) throws -> String? {
        guard let salt = hashingSalt else { return nil }
        return try hashData(data, salt: salt)
    }

    func hashData(_ data: Data, salt: Data? = nil) throws -> String? {
        guard let salt = salt ?? hashingSalt else {
            return nil
        }

        let saltedData = salt + data
        let hashedData = SHA256.hash(data: saltedData)
        let base64String = hashedData.dataRepresentation.base64EncodedString(options: [])
        return base64String
    }

    var hashingSalt: Data? {
        guard let salt = getSaltFromKeyChain() else {
            return generateSalt()
        }
        return salt
    }

    // MARK: - Generic Private Functions For Salt Generation

    private func getSaltFromKeyChain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: self.keychainServiceName as CFString,
            kSecAttrAccount: self.keychainAccountName as CFString,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data {
            return data
        }

        return nil
    }

    private func generateSalt() -> Data? {
        let length = 64
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
        }

        if result != errSecSuccess {
            return nil
        }

        let base64String = data.base64EncodedString()
        guard let base64Data = base64String.data(using: .utf8) else {
            return nil
        }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: self.keychainServiceName as CFString,
            kSecAttrAccount: self.keychainAccountName as CFString,
            kSecValueData: base64Data
        ]

        DispatchQueue.global().async {
            SecItemAdd(addQuery as CFDictionary, nil)
        }

        return data
    }

}

// MARK: - ContiguousBytes Extension

public extension ContiguousBytes {

    var dataRepresentation: Data {
        return self.withUnsafeBytes { bytes in
            return Data(bytes)
        }
    }

}
