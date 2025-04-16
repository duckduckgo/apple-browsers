//
//  EmailKeychainManager.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public class EmailKeychainManager {

    public init(needsMigration: Bool = true) {
        if needsMigration {
            Self.migrateItemsToDataProtectionKeychain()
        }
    }

}

extension EmailKeychainManager: EmailManagerStorage {

    public func getUsername() throws -> String? {
        try EmailKeychainManager.getString(forField: .username)
    }

    public func getToken() throws -> String? {
        try EmailKeychainManager.getString(forField: .token)
    }

    public func getAlias() throws -> String? {
        try EmailKeychainManager.getString(forField: .alias)
    }

    public func getCohort() throws -> String? {
        try EmailKeychainManager.getString(forField: .cohort)
    }

    public func getLastUseDate() throws -> String? {
        try EmailKeychainManager.getString(forField: .lastUseDate)
    }

    public func store(token: String, username: String, cohort: String?) throws {
        try EmailKeychainManager.add(token: token, forUsername: username, cohort: cohort)
    }

    public func store(alias: String) throws {
        try EmailKeychainManager.add(alias: alias)
    }

    public func store(lastUseDate: String) throws {
        try EmailKeychainManager.add(lastUseDate: lastUseDate)
    }

    public func deleteAlias() throws {
        try EmailKeychainManager.deleteItem(forField: .alias)
    }

    public func deleteAuthenticationState() throws {
        try EmailKeychainManager.deleteAuthenticationState()
    }

    public func deleteWaitlistState() throws {
        try EmailKeychainManager.deleteWaitlistState()
    }

}

private extension EmailKeychainManager {

    /*
     Uses just kSecAttrService as the primary key, since we don't want to store
     multiple accounts/tokens at the same time
    */
    enum EmailKeychainField: String, CaseIterable {
        case username = ".email.username"
        case token = ".email.token"
        case alias = ".email.alias"
        case lastUseDate = ".email.lastUseDate"
        case waitlistToken = ".email.waitlistToken"
        case waitlistTimestamp = ".email.waitlistTimestamp"
        case inviteCode = ".email.inviteCode"
        case cohort = ".email.cohort"

        var keyValue: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + rawValue
        }
    }

    static func getString(forField field: EmailKeychainField) throws -> String? {
        guard let data = try retrieveData(forField: field) else {
            return nil
        }

        if let decodedString = String(data: data, encoding: String.Encoding.utf8) {
            return decodedString
        } else {
            throw EmailKeychainAccessError.failedToDecodeKeychainDataAsString
        }
    }

    static func retrieveData(forField field: EmailKeychainField, useDataProtectionKeychain: Bool = true) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrService as String: field.keyValue,
            kSecReturnData as String: true,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let existingItem = item as? Data {
                return existingItem
            } else {
                throw EmailKeychainAccessError.failedToDecodeKeychainValueAsData
            }
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw EmailKeychainAccessError.keychainLookupFailure(status)
        }
    }

    static func add(token: String, forUsername username: String, cohort: String?) throws {
        guard let tokenData = token.data(using: .utf8),
              let usernameData = username.data(using: .utf8) else {
            return
        }

        try deleteAuthenticationState()

        try add(data: tokenData, forField: .token)

        do {
            try add(data: usernameData, forField: .username)
        } catch let EmailKeychainAccessError.keychainSaveFailure(status) {
            throw EmailKeychainAccessError.keychainFailedToSaveUsernameAfterSavingToken(status)
        }

        if let cohortData = cohort?.data(using: .utf8) {
            try add(data: cohortData, forField: .cohort)
        }
    }

    static func add(alias: String) throws {
        try add(string: alias, forField: .alias)
    }

    static func add(lastUseDate: String) throws {
        try add(string: lastUseDate, forField: .lastUseDate)
    }

    static func add(string: String, forField field: EmailKeychainField) throws {
        guard let stringData = string.data(using: .utf8) else {
            return
        }

        try deleteItem(forField: field)
        try add(data: stringData, forField: field)
    }

    static func add(data: Data, forField field: EmailKeychainField, useDataProtectionKeychain: Bool = true) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrSynchronizable: false,
            kSecAttrService: field.keyValue,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: data,
            kSecUseDataProtectionKeychain: useDataProtectionKeychain] as [String: Any]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            throw EmailKeychainAccessError.keychainSaveFailure(status)
        }
    }

    static func deleteAuthenticationState() throws {
        try deleteItem(forField: .username)
        try deleteItem(forField: .token)
        try deleteItem(forField: .alias)
        try deleteItem(forField: .cohort)
        try deleteItem(forField: .lastUseDate)
    }

    static func deleteItem(forField field: EmailKeychainField, useDataProtectionKeychain: Bool = true) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: field.keyValue,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw EmailKeychainAccessError.keychainDeleteFailure(status)
        }
    }

}

// MARK: - Debugging Extensions

public extension EmailKeychainManager {

    static func deleteInviteCode() throws {
        try deleteItem(forField: .inviteCode)
    }

    static func deleteWaitlistState() throws {
        try deleteItem(forField: .waitlistToken)
        try deleteItem(forField: .waitlistTimestamp)
        try deleteItem(forField: .inviteCode)
    }

}

// MARK: - Keychain Migration Extensions

extension EmailKeychainManager {

    /// Takes data from the login keychain and moves it to the data protection keychain.
    /// Reference: https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain
    static func migrateItemsToDataProtectionKeychain() {
        #if os(macOS)

        for field in EmailKeychainField.allCases {
            if let data = try? retrieveData(forField: field, useDataProtectionKeychain: false) {
                try? add(data: data, forField: field, useDataProtectionKeychain: true)
                try? deleteItem(forField: field, useDataProtectionKeychain: false)
            }
        }

        #endif
    }

}
