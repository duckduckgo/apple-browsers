//
//  SubscriptionTokenKeychainStorage.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common

public final class SubscriptionTokenKeychainStorage: SubscriptionTokenStoring {

    private let keychainType: KeychainType
    let errorHandler: ((AccountKeychainAccessType, AccountKeychainAccessError) -> Void)?

    public init(keychainType: KeychainType = .dataProtection(.unspecified),
                errorHandler: ((AccountKeychainAccessType, AccountKeychainAccessError) -> Void)? = nil) {
        self.keychainType = keychainType
        self.errorHandler = errorHandler
    }

    public func getAccessToken() throws -> String? {
        try getString(forField: .accessToken)
    }

    public func store(accessToken: String) throws {
        try set(string: accessToken, forField: .accessToken)
    }

    public func removeAccessToken() throws {
        try deleteItem(forField: .accessToken)
    }
}

private extension SubscriptionTokenKeychainStorage {

    /*
     Uses just kSecAttrService as the primary key, since we don't want to store
     multiple accounts/tokens at the same time
    */
    enum AccountKeychainField: String, CaseIterable {
        case accessToken = "subscription.account.accessToken"
        case testString = "subscription.account.testString"

        var keyValue: String {
            "com.duckduckgo" + "." + rawValue
        }
    }

    func getString(forField field: AccountKeychainField) throws -> String? {
        guard let data = try retrieveData(forField: field) else {
            return nil
        }

        if let decodedString = String(data: data, encoding: String.Encoding.utf8) {
            return decodedString
        } else {
            throw AccountKeychainAccessError.failedToDecodeKeychainDataAsString
        }
    }

    func retrieveData(forField field: AccountKeychainField) throws -> Data? {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let existingItem = item as? Data {
                return existingItem
            } else {
                throw AccountKeychainAccessError.failedToDecodeKeychainValueAsData
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw AccountKeychainAccessError.keychainLookupFailure(status)
        }
    }

    func set(string: String, forField field: AccountKeychainField) throws {
        guard let stringData = string.data(using: .utf8) else {
            return
        }

        try store(data: stringData, forField: field)
    }

    func store(data: Data, forField field: AccountKeychainField) throws {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = updateData(data, forField: field)

            if updateStatus != errSecSuccess {
                throw AccountKeychainAccessError.keychainSaveFailure(status)
            }
        default:
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    private func updateData(_ data: Data, forField field: AccountKeychainField) -> OSStatus {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue

        let newAttributes = [
          kSecValueData: data,
          kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString: Any]

        return SecItemUpdate(query as CFDictionary, newAttributes as CFDictionary)
    }

    func deleteItem(forField field: AccountKeychainField, useDataProtectionKeychain: Bool = true) throws {
        let query = defaultAttributes()

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw AccountKeychainAccessError.keychainDeleteFailure(status)
        }
    }

    private func defaultAttributes() -> [CFString: Any] {
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false
        ]
        attributes.merge(keychainType.queryAttributes()) { $1 }
        return attributes
    }
}
