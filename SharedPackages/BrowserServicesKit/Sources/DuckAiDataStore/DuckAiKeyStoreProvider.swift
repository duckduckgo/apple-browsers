//
//  DuckAiKeyStoreProvider.swift
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

import CryptoKit
import Foundation
import SecureStorage

/// Manages a single SQLCipher encryption key for the DuckAi native data store.
public final class DuckAiKeyStoreProvider {

    private static let keychainServiceName = "DuckDuckGo DuckAi Storage"
    private static let keychainAccount = "DuckAiNativeDataStore-EncryptionKey"

    private let keychainService: KeychainService
    private let accessGroup: String?

    /// - Parameter accessGroup: Keychain access group for sharing the key across
    ///   processes (e.g. app + extension). Pass `nil` for device-local only (macOS).
    public init(keychainService: KeychainService = DefaultKeychainService(), accessGroup: String? = nil) {
        self.keychainService = keychainService
        self.accessGroup = accessGroup
    }

    /// Returns the existing encryption key or generates and stores a new one.
    public func getOrCreateKey() throws -> Data {
        if let existing = try readKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return try storeKey(key)
    }

    /// Removes the encryption key from the Keychain.
    public func deleteKey() throws {
        let query = baseAttributes()
        let status = keychainService.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DuckAiNativeDataStoreError.keychainError(status: status)
        }
    }

    // MARK: - Keychain Operations

    private func baseAttributes() -> [String: Any] {
        var attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrSynchronizable as String: false
        ]
        if let accessGroup {
            attrs[kSecAttrAccessGroup as String] = accessGroup
        }
        return attrs
    }

    private func readKey() throws -> Data? {
        var query = baseAttributes()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = keychainService.itemMatching(query, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw DuckAiNativeDataStoreError.keychainError(status: status)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw DuckAiNativeDataStoreError.keychainError(status: status)
        }
    }

    private func storeKey(_ key: Data) throws -> Data {
        var query = baseAttributes()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = key

        let status = keychainService.add(query, nil)

        switch status {
        case errSecSuccess:
            return key
        case errSecDuplicateItem:
            // Another process won the race — use its key, not ours.
            guard let existing = try readKey() else {
                throw DuckAiNativeDataStoreError.keychainError(status: status)
            }
            return existing
        default:
            throw DuckAiNativeDataStoreError.keychainError(status: status)
        }
    }
}
