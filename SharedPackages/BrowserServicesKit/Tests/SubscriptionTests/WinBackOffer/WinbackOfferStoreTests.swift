//
//  WinbackOfferStoreTests.swift
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

import XCTest
import Persistence
import PersistenceTestingUtils
import SecureStorage
@testable import Subscription

final class WinbackOfferStoreTests: XCTestCase {

    var mockKeychainService: MockKeychainService!
    var mockKeyValueStore: MockThrowingKeyValueStore!
    var store: WinbackOfferStore!

    override func setUp() {
        super.setUp()
        mockKeychainService = MockKeychainService()
        mockKeyValueStore = MockThrowingKeyValueStore()
        store = WinbackOfferStore(keychainService: mockKeychainService, keyValueStore: mockKeyValueStore)
    }

    override func tearDown() {
        store = nil
        mockKeyValueStore = nil
        mockKeychainService = nil
        super.tearDown()
    }

    func testItStoresAndGetsChurnDate() {
        // Given
        let churnDate = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC

        // When
        store.storeChurnDate(churnDate)

        // Then
        let retrievedDate = store.getChurnDate()
        XCTAssertNotNil(retrievedDate)
        XCTAssertEqual(retrievedDate!.timeIntervalSince1970, churnDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testWhenNoChurnDateIsStored_ItReturnsNil() {
        // When
        let retrievedDate = store.getChurnDate()

        // Then
        XCTAssertNil(retrievedDate)
    }

    func testWhenStoringChurnDateItOverwritesPreviousValue() {
        // Given
        let firstDate = Date(timeIntervalSince1970: 1704067200)
        let secondDate = Date(timeIntervalSince1970: 1704153600)

        // When
        store.storeChurnDate(firstDate)
        store.storeChurnDate(secondDate)

        // Then
        let retrievedDate = store.getChurnDate()
        XCTAssertNotNil(retrievedDate)
        XCTAssertEqual(retrievedDate!.timeIntervalSince1970, secondDate.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Offer redemption

    func testItStoresAndGetsOfferRedemption() {
        // When
        store.setHasRedeemedOffer(true)

        // Then
        XCTAssertTrue(store.hasRedeemedOffer())
    }

    func testWhenOfferHasNotBeenRedeemed_ItReturnsFalse() {
        // When
        let hasRedeemed = store.hasRedeemedOffer()

        // Then
        XCTAssertFalse(hasRedeemed)
    }

    func testWhenSettingOfferRedemptionToFalse_ItReturnsFalse() {
        // Given
        store.setHasRedeemedOffer(true)

        // When
        store.setHasRedeemedOffer(false)

        // Then
        XCTAssertFalse(store.hasRedeemedOffer())
    }

    // MARK: - First day modal

    func testWhenFirstDayModalShownIsNotSet_ItReturnsFalse() {
        // When
        let shown = store.firstDayModalShown

        // Then
        XCTAssertFalse(shown)
    }

    func testWhenSettingFirstDayModalShownToTrue_ItReturnsTrue() {
        // When
        store.firstDayModalShown = true

        // Then
        XCTAssertTrue(store.firstDayModalShown)
    }

    func testWhenSettingFirstDayModalShownToFalse_ItReturnsFalse() {
        // Given
        store.firstDayModalShown = true

        // When
        store.firstDayModalShown = false

        // Then
        XCTAssertFalse(store.firstDayModalShown)
    }

    // MARK: - Integration

    func testItCanStoreAndRetrieveMultipleValues() {
        // Given
        let churnDate = Date(timeIntervalSince1970: 1704067200)

        // When
        store.storeChurnDate(churnDate)
        store.setHasRedeemedOffer(true)
        store.firstDayModalShown = true

        // Then
        XCTAssertEqual(store.getChurnDate()!.timeIntervalSince1970, churnDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertTrue(store.hasRedeemedOffer())
        XCTAssertTrue(store.firstDayModalShown)
    }
}

// MARK: - Mocks

class MockKeychainService: KeychainService {
    private var storage: [String: Data] = [:]

    func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard let account = query[kSecAttrAccount as String] as? String,
              let service = query[kSecAttrService as String] as? String else {
            return errSecParam
        }

        let key = "\(service).\(account)"
        if let data = storage[key] {
            result?.pointee = data as CFTypeRef
            return errSecSuccess
        }

        return errSecItemNotFound
    }

    func add(_ attributes: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard let account = attributes[kSecAttrAccount as String] as? String,
              let service = attributes[kSecAttrService as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }

        let key = "\(service).\(account)"
        if storage[key] != nil {
            return errSecDuplicateItem
        }

        storage[key] = data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        guard let account = query[kSecAttrAccount as String] as? String,
              let service = query[kSecAttrService as String] as? String else {
            return errSecParam
        }

        let key = "\(service).\(account)"
        if storage[key] != nil {
            storage.removeValue(forKey: key)
            return errSecSuccess
        }

        return errSecItemNotFound
    }

    func update(_ query: [String: Any], _ attributesToUpdate: [String: Any]) -> OSStatus {
        guard let account = query[kSecAttrAccount as String] as? String,
              let service = query[kSecAttrService as String] as? String,
              let data = attributesToUpdate[kSecValueData as String] as? Data else {
            return errSecParam
        }

        let key = "\(service).\(account)"
        if storage[key] != nil {
            storage[key] = data
            return errSecSuccess
        }

        return errSecItemNotFound
    }
}
