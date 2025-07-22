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
    private let errorEventsHandler: (AccountKeychainAccessType, AccountKeychainAccessError) -> Void
    private let accessQueue = DispatchQueue(label: "keychain.subscription.access", qos: .userInitiated)
    private let keychainOperations: KeychainOperationsProtocol

    public init(keychainType: KeychainType = .dataProtection(.unspecified),
                errorEventsHandler: @escaping (AccountKeychainAccessType, AccountKeychainAccessError) -> Void,
                keychainOperations: KeychainOperationsProtocol = DefaultKeychainOperations()) {
        self.keychainType = keychainType
        self.errorEventsHandler = errorEventsHandler
        self.keychainOperations = keychainOperations
    }

    public func getTokenContainer() throws -> TokenContainer? {
        return try accessQueue.sync {
            do {
                guard let data = try retrieveData(forField: .tokenContainer) else {
                    Logger.subscriptionKeychain.debug("TokenContainer not found")
                    return nil
                }
                return CodableHelper.decode(jsonData: data)
            } catch {
                if let error = error as? AccountKeychainAccessError {
                    errorEventsHandler(AccountKeychainAccessType.getAuthToken, error)
                } else {
                    assertionFailure("Unexpected error: \(error)")
                    Logger.subscriptionKeychain.fault("Unexpected error: \(error, privacy: .public)")
                }
                throw error
            }
        }
    }

    public func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        try accessQueue.sync {
            do {
                guard let tokenContainer else {
                    Logger.subscriptionKeychain.debug("Remove TokenContainer")
                    try self.deleteItem(forField: .tokenContainer)
                    return
                }

                guard let data = CodableHelper.encode(tokenContainer) else {
                    throw AccountKeychainAccessError.failedToEncodeKeychainData // Fixed error name
                }

                try self.store(data: data, forField: .tokenContainer)
            } catch {
                Logger.subscriptionKeychain.fault("Failed to set TokenContainer: \(error, privacy: .public)")
                if let error = error as? AccountKeychainAccessError {
                    errorEventsHandler(AccountKeychainAccessType.storeAuthToken, error)
                } else {
                    assertionFailure("Unexpected error: \(error)")
                    Logger.subscriptionKeychain.fault("Unexpected error: \(error, privacy: .public)")
                }
                throw error
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
        let status = keychainOperations.copyMatching(query as CFDictionary, &item)

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

        let status = keychainOperations.add(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            Logger.subscriptionKeychain.debug("Successfully added keychain item for \(field.keyValue)")
            return
        case errSecDuplicateItem:
            Logger.subscriptionKeychain.debug("Keychain item exists, updating for \(field.keyValue)")
            let updateStatus = updateData(data, forField: field)
            guard updateStatus == errSecSuccess else {
                Logger.subscriptionKeychain.error("Failed to update keychain item: \(updateStatus)")
                throw AccountKeychainAccessError.keychainSaveFailure(updateStatus)
            }
            Logger.subscriptionKeychain.debug("Successfully updated keychain item for \(field.keyValue)")
        default:
            Logger.subscriptionKeychain.error("Failed to add keychain item: \(status.humanReadableDescription)")
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

        let status = keychainOperations.update(query as CFDictionary, newAttributes as CFDictionary)

        if status != errSecSuccess {
            Logger.subscriptionKeychain.error("SecItemUpdate failed with status: \(status.humanReadableDescription) for field: \(field.keyValue)")
        }

        return status
    }

    func deleteItem(forField field: SubscriptionKeychainField) throws {
        var query = defaultAttributes()
        query[kSecAttrService] = field.keyValue

        let status = keychainOperations.delete(query as CFDictionary)

        if status == errSecSuccess {
            Logger.subscriptionKeychain.debug("Successfully deleted keychain item for \(field.keyValue)")
        } else if status == errSecItemNotFound {
            Logger.subscriptionKeychain.debug("Keychain item not found for deletion: \(field.keyValue)")
        } else {
            Logger.subscriptionKeychain.error("Failed to delete keychain item: \(status.humanReadableDescription)")
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
