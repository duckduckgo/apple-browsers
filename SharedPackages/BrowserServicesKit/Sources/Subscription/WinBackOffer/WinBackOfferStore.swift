//
//  WinBackOfferStore.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Persistence
import SecureStorage

/// Stores data to be used for the win-back offer feature.
public protocol WinbackOfferStoring {
    func storeChurnDate(_ churnDate: Date)
    func getChurnDate() -> Date?
    func setHasRedeemedOffer(_ didRedeem: Bool)
    func hasRedeemedOffer() -> Bool
    var firstDayModalShown: Bool { get set }
    var didDismissUrgencyMessage: Bool { get set }
}
extension WinbackOfferStore {
    enum Key: String {
        case firstDayModalShown = "winback-offer.first-day-modal-shown"
        case didDismissUrgencyMessage = "winback-offer.did-dismiss-urgency-message"
    }

    private enum KeychainKey: String {
        case churnDate
        case offerRedemption

        var accountName: String {
            (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + "." + rawValue
        }
    }
}

/// Default implementation of the WinbackOfferStoring protocol.
/// 
/// Will store the following data in Keychain:
/// - churnDate
/// - offerRedemption
/// 
/// And in user defaults:
/// - firstDayModalShown
/// - didDismissUrgencyMessage
public struct WinbackOfferStore: WinbackOfferStoring {
    private let keychainService: KeychainService
    private let keyValueStore: ThrowingKeyValueStoring
    private let serviceName = "com.duckduckgo.winback-offer"

    public init(keychainService: KeychainService = DefaultKeychainService(),
                keyValueStore: ThrowingKeyValueStoring) {
        self.keychainService = keychainService
        self.keyValueStore = keyValueStore
    }

    public var firstDayModalShown: Bool {
        get { (try? keyValueStore.object(forKey: Key.firstDayModalShown.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.firstDayModalShown.rawValue) }
    }

    public func getChurnDate() -> Date? {
        guard let data = try? retrieveData(forKey: .churnDate),
              let timeInterval = try? JSONDecoder().decode(TimeInterval.self, from: data) else {
            return nil
        }
        return Date(timeIntervalSince1970: timeInterval)
    }

    public func storeChurnDate(_ churnDate: Date) {
        let timeInterval = churnDate.timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(timeInterval) else { return }
        try? storeData(data, forKey: .churnDate)
    }

    public func setHasRedeemedOffer(_ didRedeem: Bool) {
        guard let data = try? JSONEncoder().encode(didRedeem) else { return }
        try? storeData(data, forKey: .offerRedemption)
    }

    public func hasRedeemedOffer() -> Bool {
        guard let data = try? retrieveData(forKey: .offerRedemption),
              let didRedeem = try? JSONDecoder().decode(Bool.self, from: data) else {
            return false
        }
        return didRedeem
    }

    public var didDismissUrgencyMessage: Bool {
        get { (try? keyValueStore.object(forKey: Key.didDismissUrgencyMessage.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.didDismissUrgencyMessage.rawValue) }
    }
}

// MARK: - Keychain access

extension WinbackOfferStore {
    private func retrieveData(forKey key: KeychainKey) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.accountName,
            kSecReturnData as String: true,
            kSecUseDataProtectionKeychain as String: false
        ]

        var item: CFTypeRef?
        let status = keychainService.itemMatching(query, &item)

        if status == errSecSuccess {
            return item as? Data
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw SecureStorageError.keystoreError(status: status)
        }
    }

    private func storeData(_ data: Data, forKey key: KeychainKey) throws {
        try? deleteData(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.accountName,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: data,
            kSecUseDataProtectionKeychain as String: false
        ]

        let status = keychainService.add(query, nil)

        if status != errSecSuccess {
            throw SecureStorageError.keystoreError(status: status)
        }
    }

    private func deleteData(forKey key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.accountName,
            kSecUseDataProtectionKeychain as String: false
        ]

        let status = keychainService.delete(query)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw SecureStorageError.keystoreError(status: status)
        }
    }
}
