//
//  SyncAutoRestoreDecisionStore.swift
//  DuckDuckGo
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

import Foundation
import Security

protocol SyncAutoRestoreDecisionStoring {
    func getDecision() throws -> Bool?
    func setDecision(_ decision: Bool) throws
    func clearDecision() throws
}

enum SyncAutoRestoreDecisionStoreError: Error {
    case failedToRead(OSStatus)
    case failedToWrite(OSStatus)
    case failedToDelete(OSStatus)
    case failedToDecodeDecision
}

final class SyncAutoRestoreDecisionStore: SyncAutoRestoreDecisionStoring {

    func getDecision() throws -> Bool? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw SyncAutoRestoreDecisionStoreError.failedToDecodeDecision
            }
            return try decodeDecision(from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw SyncAutoRestoreDecisionStoreError.failedToRead(status)
        }
    }

    func setDecision(_ decision: Bool) throws {
        let data = Data([decision ? UInt8(1) : UInt8(0)])

        var query = baseQuery
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw SyncAutoRestoreDecisionStoreError.failedToWrite(status)
        }
    }

    func clearDecision() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SyncAutoRestoreDecisionStoreError.failedToDelete(status)
        }
    }

    private func decodeDecision(from data: Data) throws -> Bool {
        guard let value = data.first else {
            throw SyncAutoRestoreDecisionStoreError.failedToDecodeDecision
        }

        switch value {
        case 0:
            return false
        case 1:
            return true
        default:
            throw SyncAutoRestoreDecisionStoreError.failedToDecodeDecision
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: Constants.keychainAccount,
            kSecAttrSynchronizable as String: false
        ]
    }

    private var serviceName: String {
        keychainServiceName(suffix: Constants.serviceSuffix)
    }

    private func keychainServiceName(suffix: String) -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? Constants.defaultBundleIdentifier
        return "\(bundleIdentifier).\(suffix)"
    }

    private enum Constants {
        static let serviceSuffix = "sync.auto-restore.decision"
        static let keychainAccount = "decision"
        static let defaultBundleIdentifier = "com.duckduckgo"
    }
}
