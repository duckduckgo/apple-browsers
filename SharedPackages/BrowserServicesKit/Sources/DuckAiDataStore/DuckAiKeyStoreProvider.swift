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

/// Manages a single SQLCipher encryption key for the DuckAi native data store.
///
/// Unlike the full SecureVault key hierarchy (L1/L2/L3), DuckAi only needs
/// database-level encryption — one symmetric key stored in the Keychain.
public final class DuckAiKeyStoreProvider {

    private static let keychainService = "DuckDuckGo DuckAi Storage"
    private static let keychainAccount = "DuckAiNativeDataStore-EncryptionKey"

    private let keychainService: KeychainServicing

    public init(keychainService: KeychainServicing = DefaultKeychainService()) {
        self.keychainService = keychainService
    }

    /// Returns the existing encryption key or generates and stores a new one.
    public func getOrCreateKey() throws -> Data {
        if let existing = try readKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try storeKey(key)
        return key
    }

    // MARK: - Keychain Operations

    private func readKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

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

    private func storeKey(_ key: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: key
        ]

        let status = keychainService.add(query, nil)
        guard status == errSecSuccess else {
            throw DuckAiNativeDataStoreError.keychainError(status: status)
        }
    }
}

// MARK: - Keychain Abstraction

/// Protocol wrapping Keychain operations to enable testing.
public protocol KeychainServicing {
    func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func add(_ attributes: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
}

public struct DefaultKeychainService: KeychainServicing {
    public init() {}

    public func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, result)
    }

    public func add(_ attributes: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
