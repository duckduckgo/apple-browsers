//
//  MockAIChatBonusKeychainService.swift
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
import SecureStorage

/// A single-item in-memory Keychain. Each status override makes that call fail without touching the item.
final class MockAIChatBonusKeychainService: KeychainService {

    var storedData: Data?
    /// Returned in place of `storedData` on a successful read, e.g. to simulate a non-`Data` item.
    var itemOverride: CFTypeRef?

    var itemMatchingStatus: OSStatus?
    var addStatus: OSStatus?
    var updateStatuses: [OSStatus] = []
    var deleteStatus: OSStatus?

    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var latestItemMatchingQuery: [String: Any] = [:]
    private(set) var latestAddAttributes: [String: Any] = [:]
    private(set) var latestUpdateQuery: [String: Any] = [:]
    private(set) var latestUpdateAttributes: [String: Any] = [:]
    private(set) var latestDeleteQuery: [String: Any] = [:]

    func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        latestItemMatchingQuery = query
        if let itemMatchingStatus {
            return itemMatchingStatus
        }
        if let itemOverride {
            result?.pointee = itemOverride
            return errSecSuccess
        }
        guard let storedData else {
            return errSecItemNotFound
        }
        result?.pointee = storedData as CFData
        return errSecSuccess
    }

    func add(_ attributes: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        addCallCount += 1
        latestAddAttributes = attributes
        if let addStatus {
            return addStatus
        }
        guard storedData == nil else {
            return errSecDuplicateItem
        }
        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(_ query: [String: Any], _ attributesToUpdate: [String: Any]) -> OSStatus {
        updateCallCount += 1
        latestUpdateQuery = query
        latestUpdateAttributes = attributesToUpdate
        if !updateStatuses.isEmpty {
            return updateStatuses.removeFirst()
        }
        guard storedData != nil else {
            return errSecItemNotFound
        }
        storedData = attributesToUpdate[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteCallCount += 1
        latestDeleteQuery = query
        if let deleteStatus {
            return deleteStatus
        }
        guard storedData != nil else {
            return errSecItemNotFound
        }
        storedData = nil
        return errSecSuccess
    }
}
