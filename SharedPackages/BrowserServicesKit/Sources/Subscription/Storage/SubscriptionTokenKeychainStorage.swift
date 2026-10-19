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
import os.log
import Networking
import Common
import FoundationExtensions

public enum KeychainErrorSource: String {
    case browser
    case vpn
    case pir
}

public enum KeychainErrorAuthVersion: String {
    case v1
    case v2
}

public final class SubscriptionTokenKeychainStorage: AuthTokenStoring {

    private let errorEventsHandler: (AccountKeychainAccessType, AccountKeychainAccessError) -> Void
    private let keychainManager: any KeychainManaging
    private let userDefaults: UserDefaults
    private let field: SubscriptionKeychainField

    /// - Parameters:
    ///   - keychainManager: Reads and writes the keychain item.
    ///   - userDefaults: Stores whether a token is expected to be found, used to report unexpected misses.
    ///   - field: The keychain item this storage reads and writes.
    ///   - errorEventsHandler: Receives keychain access errors, including a missing token that was expected.
    public init(keychainManager: any KeychainManaging,
                userDefaults: UserDefaults,
                field: SubscriptionKeychainField = .tokenContainer,
                errorEventsHandler: @escaping (AccountKeychainAccessType, AccountKeychainAccessError) -> Void) {
        self.errorEventsHandler = errorEventsHandler
        self.keychainManager = keychainManager
        self.userDefaults = userDefaults
        self.field = field
    }

    /*
     Uses just kSecAttrService as the primary key, since we don't want to store
     multiple accounts/tokens at the same time
     */
    /// The keychain items a `SubscriptionTokenKeychainStorage` can target.
    public enum SubscriptionKeychainField: String, CaseIterable {
        /// The token container used by the app and its extensions.
        case tokenContainer = "subscription.v2.tokens"
        /// A second, independent token container kept by the main app.
        case backupTokenContainer = "subscription.v2.tokens.backup"

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
            guard let data = try keychainManager.retrieveData(forKey: field.keyValue) else {
                Logger.subscriptionKeychain.log("Token container not found: \(self.field.rawValue, privacy: .public)")
                verifyTokenNotFoundExpectation()
                return nil
            }
            let result: TokenContainer? = CodableHelper.decode(jsonData: data)
            if result == nil {
                Logger.subscriptionKeychain.error("Failed to decode the token container: \(self.field.rawValue, privacy: .public)")
                verifyTokenNotFoundExpectation()
            }
            return result
        } catch {
            verifyTokenNotFoundExpectation()
            if let error = error as? AccountKeychainAccessError {
                errorEventsHandler(AccountKeychainAccessType.getAuthToken, error)
            } else {
                assertionFailure("Unexpected error: \(error)")
                Logger.subscriptionKeychain.fault("Unexpected error reading the token container \(self.field.rawValue, privacy: .public): \(error, privacy: .public)")
            }
            throw error
        }
    }

    public func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        tokenExpected = tokenContainer != nil

        do {
            guard let tokenContainer else {
                Logger.subscriptionKeychain.log("Deleting the token container: \(self.field.rawValue, privacy: .public)")
                try keychainManager.deleteItem(forKey: field.keyValue)
                return
            }

            Logger.subscriptionKeychain.log("Saving the token container: \(self.field.rawValue, privacy: .public)")

            guard let data = CodableHelper.encode(tokenContainer) else {
                throw AccountKeychainAccessError.failedToEncodeKeychainData // Fixed error name
            }

            try keychainManager.store(data: data, forKey: field.keyValue)
        } catch {
            Logger.subscriptionKeychain.error("Failed to update the token container \(self.field.rawValue, privacy: .public): \(error, privacy: .public)")
            if let error = error as? AccountKeychainAccessError {
                errorEventsHandler(AccountKeychainAccessType.storeAuthToken, error)
            } else {
                assertionFailure("Unexpected error: \(error)")
            }
            throw error
        }
    }

    private func verifyTokenNotFoundExpectation() {
        if tokenExpected {
            Logger.subscriptionKeychain.error("Expected token container not found: \(self.field.rawValue, privacy: .public)")
            errorEventsHandler(AccountKeychainAccessType.getAuthToken, AccountKeychainAccessError.expectedTokenNotFound)
            tokenExpected = false
        }
    }

    private var tokenExpectedKey: String { field.keyValue + ".expected" }
    private var tokenExpected: Bool {
        get { userDefaults.bool(forKey: tokenExpectedKey) }
        set { userDefaults.set(newValue, forKey: tokenExpectedKey) }
    }
}
