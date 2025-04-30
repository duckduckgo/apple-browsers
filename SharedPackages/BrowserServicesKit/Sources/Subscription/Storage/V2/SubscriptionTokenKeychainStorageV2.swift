//
//  SubscriptionTokenKeychainStorageV2.swift
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
import os.log
import Networking
import Common

public enum KeychainErrorSource: String {
    case browser
    case vpn
    case pir
    case shared
}

public enum KeychainErrorAuthVersion: String {
    case v1
    case v2
}

public final class SubscriptionTokenKeychainStorageV2: AuthTokenStoring {

    private let keychainType: KeychainType
    private let errorHandler: (AccountKeychainAccessType, AccountKeychainAccessError) -> Void

    public init(keychainType: KeychainType = .dataProtection(.unspecified),
                errorHandler: @escaping (AccountKeychainAccessType, AccountKeychainAccessError) -> Void) {
        self.keychainType = keychainType
        self.errorHandler = errorHandler
    }

    public var tokenContainer: TokenContainer? {
        get {
            do {
                guard let data = try retrieveData(forField: .tokenContainer) else {
                    Logger.subscriptionKeychain.debug("TokenContainer not found")
                    return nil
                }
                return CodableHelper.decode(jsonData: data)
            } catch {
                if let error = error as? AccountKeychainAccessError {
                    errorHandler(AccountKeychainAccessType.getAuthToken, error)
                } else {
                    assertionFailure("Unexpected error: \(error)")

                    Logger.subscriptionKeychain.fault("Unexpected error: \(error, privacy: .public)")
                }

                return nil
            }
        }
        set {
            do {
                guard let newValue else {
                    Logger.subscriptionKeychain.debug("Remove TokenContainer")
                    try self.deleteItem(forField: .tokenContainer)
                    return
                }

                if let data = CodableHelper.encode(newValue) {
                    try self.store(data: data, forField: .tokenContainer)
                } else {
                    throw AccountKeychainAccessError.failedToDecodeKeychainData
                }
            } catch {
                Logger.subscriptionKeychain.fault("Failed to set TokenContainer: \(error, privacy: .public)")
                if let error = error as? AccountKeychainAccessError {
                    errorHandler(AccountKeychainAccessType.storeAuthToken, error)
                } else {
                    assertionFailure("Unexpected error: \(error)")
                    Logger.subscriptionKeychain.fault("Unexpected error: \(error, privacy: .public)")
                }
            }
        }
    }
}

extension SubscriptionTokenKeychainStorageV2 {

    /*
     Uses just kSecAttrService as the primary key, since we don't want to store
     multiple accounts/tokens at the same time
     */
    enum SubscriptionKeychainField: String, CaseIterable {
        case tokenContainer = "subscription.v2.tokens"

        var keyValue: String {
            "com.duckduckgo" + "." + rawValue
        }
    }

    func retrieveData(forField field: SubscriptionKeychainField) throws -> Data? {
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
                throw AccountKeychainAccessError.failedToDecodeKeychainData
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw AccountKeychainAccessError.keychainLookupFailure(status)
        }
    }

    func store(data: Data, forField field: SubscriptionKeychainField) throws {
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

    private func updateData(_ data: Data, forField field: SubscriptionKeychainField) -> OSStatus {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue

        let newAttributes = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString: Any]

        return SecItemUpdate(query as CFDictionary, newAttributes as CFDictionary)
    }

    func deleteItem(forField field: SubscriptionKeychainField, useDataProtectionKeychain: Bool = true) throws {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue

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
