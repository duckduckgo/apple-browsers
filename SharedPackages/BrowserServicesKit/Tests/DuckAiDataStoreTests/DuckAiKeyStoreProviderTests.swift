//
//  DuckAiKeyStoreProviderTests.swift
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
import SecureStorage
import XCTest
@testable import DuckAiDataStore

final class DuckAiKeyStoreProviderTests: XCTestCase {

    private var mockKeychain: MockKeychainService!
    private var sut: DuckAiKeyStoreProvider!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
        sut = DuckAiKeyStoreProvider(keychainService: mockKeychain)
    }

    override func tearDown() {
        sut = nil
        mockKeychain = nil
        super.tearDown()
    }

    // MARK: - getOrCreateKey

    func testWhenNoKeyExistsThenGetOrCreateKeyGeneratesAndStoresOne() throws {
        let key = try sut.getOrCreateKey()

        XCTAssertEqual(key.count, 32)
        XCTAssertEqual(mockKeychain.addCallCount, 1)
    }

    func testWhenKeyExistsThenGetOrCreateKeyReturnsIt() throws {
        let existingKey = Data(repeating: 0xAB, count: 32)
        mockKeychain.storedData = existingKey

        let key = try sut.getOrCreateKey()

        XCTAssertEqual(key, existingKey)
        XCTAssertEqual(mockKeychain.addCallCount, 0)
    }

    func testWhenGetOrCreateKeyCalledTwiceThenSameKeyReturned() throws {
        let first = try sut.getOrCreateKey()
        let second = try sut.getOrCreateKey()

        XCTAssertEqual(first, second)
        XCTAssertEqual(mockKeychain.addCallCount, 1)
    }

    func testWhenReadKeyFailsThenGetOrCreateKeyThrows() {
        mockKeychain.itemMatchingStatus = errSecAuthFailed

        XCTAssertThrowsError(try sut.getOrCreateKey()) { error in
            guard case DuckAiNativeDataStoreError.keychainError(let status) = error else {
                return XCTFail("Expected keychainError, got \(error)")
            }
            XCTAssertEqual(status, errSecAuthFailed)
        }
    }

    func testWhenStoreKeyFailsThenGetOrCreateKeyThrows() {
        mockKeychain.addStatus = errSecInteractionNotAllowed

        XCTAssertThrowsError(try sut.getOrCreateKey()) { error in
            guard case DuckAiNativeDataStoreError.keychainError(let status) = error else {
                return XCTFail("Expected keychainError, got \(error)")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
    }

    func testWhenStoreKeyGetsDuplicateItemThenReadsExistingKey() throws {
        // Simulate a race: add returns duplicate, but a subsequent read succeeds
        let raceWinnerKey = Data(repeating: 0xCD, count: 32)
        mockKeychain.addStatus = errSecDuplicateItem
        mockKeychain.duplicateRaceKey = raceWinnerKey

        let key = try sut.getOrCreateKey()

        XCTAssertEqual(key, raceWinnerKey)
    }

    // MARK: - deleteKey

    func testWhenDeleteKeySucceedsThenNoError() throws {
        mockKeychain.storedData = Data(repeating: 0xAB, count: 32)
        mockKeychain.deleteStatus = errSecSuccess

        XCTAssertNoThrow(try sut.deleteKey())
        XCTAssertEqual(mockKeychain.deleteCallCount, 1)
    }

    func testWhenDeleteKeyNotFoundThenNoError() throws {
        mockKeychain.deleteStatus = errSecItemNotFound

        XCTAssertNoThrow(try sut.deleteKey())
    }

    func testWhenDeleteKeyFailsThenThrows() {
        mockKeychain.deleteStatus = errSecAuthFailed

        XCTAssertThrowsError(try sut.deleteKey()) { error in
            guard case DuckAiNativeDataStoreError.keychainError(let status) = error else {
                return XCTFail("Expected keychainError, got \(error)")
            }
            XCTAssertEqual(status, errSecAuthFailed)
        }
    }

    // MARK: - Access Group

    func testWhenAccessGroupProvidedThenKeychainQueriesIncludeIt() throws {
        let accessGroup = "com.duckduckgo.test.group"
        sut = DuckAiKeyStoreProvider(keychainService: mockKeychain, accessGroup: accessGroup)

        _ = try sut.getOrCreateKey()

        let lastQuery = mockKeychain.lastAddAttributes
        XCTAssertEqual(lastQuery?[kSecAttrAccessGroup as String] as? String, accessGroup)
    }

    func testWhenNoAccessGroupThenKeychainQueriesOmitIt() throws {
        _ = try sut.getOrCreateKey()

        let lastQuery = mockKeychain.lastAddAttributes
        XCTAssertNil(lastQuery?[kSecAttrAccessGroup as String])
    }
}

// MARK: - MockKeychainService

private final class MockKeychainService: KeychainService {

    var storedData: Data?
    var itemMatchingStatus: OSStatus = errSecSuccess
    var addStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess

    /// Key to return on read after an `errSecDuplicateItem` from add.
    var duplicateRaceKey: Data?

    private(set) var addCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastAddAttributes: [String: Any]?

    func itemMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard itemMatchingStatus == errSecSuccess else {
            return itemMatchingStatus
        }

        let dataToReturn = storedData ?? duplicateRaceKey
        guard let data = dataToReturn else {
            return errSecItemNotFound
        }
        result?.pointee = data as CFTypeRef
        return errSecSuccess
    }

    func add(_ attributes: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        addCallCount += 1
        lastAddAttributes = attributes

        guard addStatus == errSecSuccess else {
            return addStatus
        }

        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteCallCount += 1
        if deleteStatus == errSecSuccess {
            storedData = nil
        }
        return deleteStatus
    }

    func update(_ query: [String: Any], _ attributesToUpdate: [String: Any]) -> OSStatus {
        errSecSuccess
    }
}
