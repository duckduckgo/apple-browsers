//
//  SyncAutoRestoreDecisionStoreTests.swift
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

import XCTest
import Security
@testable import DuckDuckGo

final class SyncAutoRestoreDecisionStoreTests: XCTestCase {

    private static let keychainLock = NSLock()
    private var sut: SyncAutoRestoreDecisionStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        Self.keychainLock.lock()
        sut = SyncAutoRestoreDecisionStore()
        do {
            try sut.clearDecision()
        } catch {
            Self.keychainLock.unlock()
            throw XCTSkip("Skipping keychain-backed test due to unavailable keychain: \(error)")
        }
    }

    override func tearDownWithError() throws {
        defer { Self.keychainLock.unlock() }
        try? sut.clearDecision()
        sut = nil
        try super.tearDownWithError()
    }

    func testSetDecisionTrueThenGetDecisionReturnsTrue() throws {
        try sut.setDecision(true)

        XCTAssertEqual(try sut.getDecision(), true)
    }

    func testSetDecisionFalseThenGetDecisionReturnsFalse() throws {
        try sut.setDecision(false)

        XCTAssertEqual(try sut.getDecision(), false)
    }

    func testSetDecisionTwiceThenGetDecisionReturnsMostRecentValue() throws {
        try sut.setDecision(true)
        try sut.setDecision(false)

        XCTAssertEqual(try sut.getDecision(), false)
    }

    func testClearDecisionThenGetDecisionReturnsNil() throws {
        try sut.setDecision(true)

        try sut.clearDecision()

        XCTAssertNil(try sut.getDecision())
    }

    func testGetDecisionWhenStoredPayloadIsMalformedThrowsDecodeError() throws {
        try writeRawDecisionData(Data([2]))

        do {
            _ = try sut.getDecision()
            XCTFail("Expected getDecision to throw")
        } catch let error as SyncAutoRestoreDecisionStoreError {
            switch error {
            case .failedToDecodeDecision:
                break
            default:
                XCTFail("Expected failedToDecodeDecision, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func writeRawDecisionData(_ data: Data) throws {
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecAttrSynchronizable as String] = false
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreKeychainWriteError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: "decision"
        ]
    }

    private var keychainServiceName: String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.duckduckgo"
        return "\(bundleIdentifier).sync.auto-restore.decision"
    }
}

private struct StoreKeychainWriteError: Error {
    let status: OSStatus
}
