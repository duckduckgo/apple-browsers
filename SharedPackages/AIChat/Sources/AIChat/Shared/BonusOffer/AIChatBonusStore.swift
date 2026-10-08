//
//  AIChatBonusStore.swift
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

import Common
import Foundation
import Security
import SecureStorage

/// Represent a store operation failure.
public enum AIChatBonusStoreError: Error, Equatable {
    /// The Keychain read failed for a reason other than a missing item, e.g. the device is locked before its first unlock.
    case readFailed(OSStatus)
    /// The Keychain refused to add or update the item.
    case writeFailed(OSStatus)
    /// The Keychain refused to delete the item. A missing item is not a failure.
    case deleteFailed(OSStatus)
    /// The Keychain returned something other than `Data` for the item.
    case unexpectedItemType
    /// The stored bytes aren't valid JSON, or don't match the layout of their schema version.
    case decodingFailed
    /// The record couldn't be turned into JSON.
    case encodingFailed
    /// The item was written in a layout this build doesn't know, by a newer build.
    case unsupportedSchemaVersion(Int)
    /// The record breaks `AIChatBonusRecord.breaksInvariant`. Raised before a write and after a read.
    case invariantViolated
}

/// A type that can persist AI Chat Bonus data.
public protocol AIChatBonusStoring {
    /// The stored record, or `nil` only when the Keychain confirms there's no item.
    ///
    /// Any other failure throws, e.g. the device is locked or the stored data can't be decoded.
    /// If read fails do not attempt to write or delete the record and and don't push anything to Duck.ai, not even `record: null`.
    func read() throws -> AIChatBonusRecord?

    /// Saves `record` in the current layout, replacing whatever is stored.
    ///
    /// Throws `invariantViolated` without touching the Keychain if `record` is one Duck.ai would reject.
    func write(_ record: AIChatBonusRecord) throws

    /// Removes the record. Succeeds when there was nothing to remove.
    func delete() throws
}

/// Storage for AI Chat Offer data backed up by the Keychain.
///
/// Not thread-safe on its own. `AIChatBonusService` serialises every read-check-write.
public struct AIChatBonusStore: AIChatBonusStoring {
    private let keychainService: KeychainService

    public init(keychainService: KeychainService = DefaultKeychainService()) {
        self.keychainService = keychainService
    }

    public func read() throws -> AIChatBonusRecord? {
        var query = baseQuery(for: .record)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = keychainService.itemMatching(query, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw AIChatBonusStoreError.unexpectedItemType
            }
            return try decode(data)
        case errSecItemNotFound:
            return nil
        default:
            throw AIChatBonusStoreError.readFailed(status)
        }
    }

    public func write(_ record: AIChatBonusRecord) throws {
        // If record is in an inconsistent state do not store it.
        guard !record.breaksInvariant else {
            throw AIChatBonusStoreError.invariantViolated
        }

        let data = try encode(record)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Add the record, or replace it if it already exists.
        var status = keychainService.add(baseQuery(for: .record).merging(attributes) { $1 }, nil)
        if status == errSecDuplicateItem {
            status = keychainService.update(baseQuery(for: .record), attributes)
        }

        // Throw an error in case we could not write it
        guard status == errSecSuccess else {
            throw AIChatBonusStoreError.writeFailed(status)
        }
    }

    public func delete() throws {
        let status = keychainService.delete(baseQuery(for: .record))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIChatBonusStoreError.deleteFailed(status)
        }
    }
}

// MARK: - Keychain Helpers

private extension AIChatBonusStore {

    /// One Keychain item per case, all under the same service. Store something new by adding a case.
    enum AIChatBonusKeychainField: String {
        /// The bonus record. One record per device, not one per campaign.
        case record

        /// `<bundleID>.aichat.bonus-offer`, so each build (debug, review, release) keeps its own items.
        var serviceName: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + ".aichat.bonus-offer.\(rawValue)"
        }
    }

    /// The attributes that identify `field`'s Keychain item, shared by every read, write and delete.
    ///
    /// - Not synchronised, so the item never leaves this device through iCloud Keychain.
    /// - No access group, so the item goes to the app's own default group and other apps can't read it.
    /// - Data protection keychain: on macOS this picks it over the older file-based keychain, which is the default there. iOS always uses it, so the attribute changes nothing there.
    func baseQuery(for field: AIChatBonusKeychainField) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: field.serviceName,
            kSecAttrAccount as String: field.rawValue,
            kSecAttrSynchronizable as String: false
        ]
        // Adds kSecUseDataProtectionKeychain: true
        for (key, value) in KeychainType.dataProtection(.unspecified).queryAttributes() {
            query[key as String] = value
        }
        return query
    }

}

// MARK: - Encoding / Decoding

private extension AIChatBonusStore {

    // The record's Keychain format. For storage only.
    struct StoredRecord: Codable {
        /// The version of the current model layout.
        /// Bump it only for a change an older build would misread: a field renamed, removed, made required or given a new meaning or unit.
        /// A new optional field needs no bump, since older items decode it as `nil`.
        /// When bumping, keep the previous layout as a frozen `StoredRecordV<n>` type, decode it in
        /// `decode(_:)` and map it to the current `AIChatBonusRecord`.
        /// That migrates on read only: the item stays in the old layout until the next write saves it in the current one.
        static let currentSchemaVersion = 1

        /// The schema of the record
        let schemaVersion: Int
        /// The AI Chat Bonus record
        let record: AIChatBonusRecord

        init(record: AIChatBonusRecord) {
            self.schemaVersion = Self.currentSchemaVersion
            self.record = record
        }
    }

    struct StoredSchemaVersion: Decodable {
        let schemaVersion: Int
    }

    func encode(_ record: AIChatBonusRecord) throws -> Data {
        do {
            return try JSONEncoder().encode(StoredRecord(record: record))
        } catch {
            throw AIChatBonusStoreError.encodingFailed
        }
    }

    func decode(_ data: Data) throws -> AIChatBonusRecord {
        let decoder = JSONDecoder()
        // Read the version on its own first, since each version may have a different layout.
        guard let version = try? decoder.decode(StoredSchemaVersion.self, from: data).schemaVersion else {
            throw AIChatBonusStoreError.decodingFailed
        }
        // Any version other than the current one is rejected:
        // - Older: none exists yet. When the layout changes, decode the old one here and map it to the
        //   current record (see `currentSchemaVersion`).
        // - Newer: a later build wrote it, then this build replaced that newer one, e.g. a release rolled back
        //   through Sparkle. Throwing means the service never writes over a record it can't read.
        guard version == StoredRecord.currentSchemaVersion else {
            throw AIChatBonusStoreError.unsupportedSchemaVersion(version)
        }
        guard let record = try? decoder.decode(StoredRecord.self, from: data).record else {
            throw AIChatBonusStoreError.decodingFailed
        }
        guard !record.breaksInvariant else {
            throw AIChatBonusStoreError.invariantViolated
        }
        return record
    }

}
