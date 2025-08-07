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

    private let errorEventsHandler: (AccountKeychainAccessType, AccountKeychainAccessError) -> Void
    private let keychainManager: any KeychainManaging

    public init(keychainManager: any KeychainManaging,
                errorEventsHandler: @escaping (AccountKeychainAccessType, AccountKeychainAccessError) -> Void) {
        self.errorEventsHandler = errorEventsHandler
        self.keychainManager = keychainManager
    }

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

    public static func defaultAttributes(keychainType: KeychainType) -> [CFString: Any] {
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false
        ]
        attributes.merge(keychainType.queryAttributes()) { $1 }
        return attributes
    }

    public func getTokenContainer() throws -> TokenContainer? {
        do {
            guard let data = try keychainManager.retrieveData(forKey: SubscriptionKeychainField.tokenContainer.keyValue) else {
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

    public func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        do {
            guard let tokenContainer else {
                Logger.subscriptionKeychain.debug("Remove TokenContainer")
                try keychainManager.deleteItem(forKey: SubscriptionKeychainField.tokenContainer.keyValue)
                return
            }

            guard let data = CodableHelper.encode(tokenContainer) else {
                throw AccountKeychainAccessError.failedToEncodeKeychainData // Fixed error name
            }

            try keychainManager.store(data: data, forKey: SubscriptionKeychainField.tokenContainer.keyValue)
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
