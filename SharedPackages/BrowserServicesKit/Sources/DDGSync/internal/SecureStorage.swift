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

    private static let defaultQuery: [AnyHashable: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "\(Bundle.main.bundleIdentifier ?? "com.duckduckgo").sync",
        kSecAttrGeneric: encodedKey as Any,
        kSecAttrAccount: encodedKey as Any
    ]

    func persistAccount(_ account: SyncAccount) throws {
        let data = try JSONEncoder.snakeCaseKeys.encode(account)

        var query = Self.defaultQuery
        query[kSecUseDataProtectionKeychain] = true
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
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
        let status = SecItemDelete(Self.defaultQuery as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw SyncError.failedToRemoveSecureStore(status: status)
        }
    }

}
