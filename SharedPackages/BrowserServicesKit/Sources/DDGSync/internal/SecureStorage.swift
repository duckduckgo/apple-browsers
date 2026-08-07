//
//  SecureStorage.swift
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

struct SecureStorage: SecureStoring {

    // DO NOT CHANGE except if you want to deliberately invalidate all users's sync accounts.
    // The keys have a uid to deter casual hacker from easily seeing which keychain entry is related to what.
    private static let encodedKey = "833CC26A-3804-4D37-A82A-C245BC670692".data(using: .utf8)
    private static let scopedPasswordEncodedKey = "A41F3610-CA35-485B-8B74-38BC6309786D".data(using: .utf8)
    private static let protectedKeysEncodedKey = "E5F0D7A6-04F5-44FB-9AA5-68073089B749".data(using: .utf8)

    private static let defaultQuery: [AnyHashable: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "\(Bundle.main.bundleIdentifier ?? "com.duckduckgo").sync",
        kSecAttrGeneric: encodedKey as Any,
        kSecAttrAccount: encodedKey as Any
    ]

    private static let protectedKeysQuery: [AnyHashable: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "\(Bundle.main.bundleIdentifier ?? "com.duckduckgo").sync",
        kSecAttrGeneric: protectedKeysEncodedKey as Any,
        kSecAttrAccount: protectedKeysEncodedKey as Any
    ]

    private static let scopedPasswordQuery: [AnyHashable: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "\(Bundle.main.bundleIdentifier ?? "com.duckduckgo").sync",
        kSecAttrGeneric: scopedPasswordEncodedKey as Any,
        kSecAttrAccount: scopedPasswordEncodedKey as Any
    ]

    func persistAccount(_ account: SyncAccount) throws {
        let data = try JSONEncoder.snakeCaseKeys.encode(account)

        var query = Self.defaultQuery
        query[kSecUseDataProtectionKeychain] = true
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecAttrSynchronizable] = false
        query[kSecValueData] = data

        var status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [
                kSecValueData: data
            ] as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw SyncError.failedToWriteSecureStore(status: status)
        }
    }

    func account() throws -> SyncAccount? {
        var query = Self.defaultQuery
        query[kSecReturnData] = true

        var item: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToReadSecureStore(status: status)
        }

        if let data = item as? Data {
            do {
                return try JSONDecoder.snakeCaseKeys.decode(SyncAccount.self, from: data)
            } catch {
                throw SyncError.failedToDecodeSecureStoreData(error: error as NSError)
            }
        }

        return nil
    }

    func removeAccount() throws {
        try? removeScopedPassword()
        try? removeProtectedKeys()

        let status = SecItemDelete(Self.defaultQuery as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToRemoveSecureStore(status: status)
        }
    }

    func persistScopedPassword(_ scopedPassword: Data) throws {
        var query = Self.scopedPasswordQuery
        query[kSecUseDataProtectionKeychain] = true
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecAttrSynchronizable] = false
        query[kSecValueData] = scopedPassword

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [
                kSecValueData: scopedPassword
            ] as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw SyncError.failedToWriteSecureStore(status: status)
        }
    }

    func scopedPassword() throws -> Data? {
        var query = Self.scopedPasswordQuery
        query[kSecReturnData] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToReadSecureStore(status: status)
        }

        return item as? Data
    }

    func removeScopedPassword() throws {
        let status = SecItemDelete(Self.scopedPasswordQuery as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToRemoveSecureStore(status: status)
        }
    }

    func persistProtectedKeys(_ data: Data) throws {
        var query = Self.protectedKeysQuery
        query[kSecUseDataProtectionKeychain] = true
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecAttrSynchronizable] = false
        query[kSecValueData] = data

        var status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [
                kSecValueData: data
            ] as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw SyncError.failedToWriteSecureStore(status: status)
        }
    }

    func removeProtectedKeys() throws {
        let status = SecItemDelete(Self.protectedKeysQuery as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToRemoveSecureStore(status: status)
        }
    }

}
