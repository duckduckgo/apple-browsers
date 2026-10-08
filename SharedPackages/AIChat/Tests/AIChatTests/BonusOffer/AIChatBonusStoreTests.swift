//
//  AIChatBonusStoreTests.swift
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
import Testing
@testable import AIChat

@Suite("AIChatBonus - Store Tests")
struct AIChatBonusStoreTests {
    private let serviceName = (Bundle.main.bundleIdentifier ?? "com.duckduckgo") + ".aichat.bonus-offer.record"

    private let claimedRecord = AIChatBonusRecord(
        campaignName: "launch",
        bonusId: "8a7b9c1d-2e3f-4a5b-8c6d-7e8f9a0b1c2d",
        terms: AIChatBonusRecord.Terms(multiplier: 2, expiresAt: 1_790_000_000),
        lastRedeemAttemptAt: 1_780_000_000_000
    )

    private let keychain = MockAIChatBonusKeychainService()
    private let sut: AIChatBonusStore

    init() {
        sut = AIChatBonusStore(keychainService: keychain)
    }

    // MARK: - Read

    @available(iOS 16, macOS 13, *)
    @Test("Check reading with no item returns no record", .timeLimit(.minutes(1)))
    func readWithNoItemReturnsNil() throws {
        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a written record is read back", .timeLimit(.minutes(1)))
    func writtenRecordIsReadBack() throws {
        // GIVEN
        try sut.write(claimedRecord)

        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == claimedRecord)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a Keychain failure makes the read throw its status", .timeLimit(.minutes(1)), arguments: [errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed])
    func keychainFailureMakesReadThrow(_ status: OSStatus) {
        // GIVEN
        keychain.itemMatchingStatus = status

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(status)) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check an item that is not data makes the read throw", .timeLimit(.minutes(1)))
    func itemThatIsNotDataMakesReadThrow() {
        // GIVEN
        keychain.itemOverride = "not data" as CFString

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.unexpectedItemType) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check an item that is not JSON makes the read throw", .timeLimit(.minutes(1)))
    func itemThatIsNotJSONMakesReadThrow() {
        // GIVEN
        keychain.storedData = Data("garbage".utf8)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.decodingFailed) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check record fields that do not decode make the read throw", .timeLimit(.minutes(1)))
    func recordFieldsThatDoNotDecodeMakeReadThrow() {
        // GIVEN
        keychain.storedData = Data(#"{"schemaVersion":1,"record":{"dismissed":"yes"}}"#.utf8) // wrong type for `dismissed`, should be `true` or `false`

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.decodingFailed) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check an unknown schema version makes the read throw", .timeLimit(.minutes(1)))
    func unknownSchemaVersionMakesReadThrow() {
        // GIVEN
        keychain.storedData = Data(#"{"schemaVersion":2,"somethingNew":true}"#.utf8)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.unsupportedSchemaVersion(2)) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a stored record that breaks the invariant makes the read throw", .timeLimit(.minutes(1)))
    func storedRecordThatBreaksTheInvariantMakesReadThrow() {
        // GIVEN
        keychain.storedData = Data(#"{"schemaVersion":1,"record":{"bonusId":"id","dismissed":false}}"#.utf8)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.invariantViolated) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check the read queries the bonus item", .timeLimit(.minutes(1)))
    func readQueriesTheBonusItem() throws {
        // WHEN
        _ = try sut.read()

        // THEN
        let query = keychain.latestItemMatchingQuery
        expectBaseQuery(query)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
    }

    // MARK: - Write

    @available(iOS 16, macOS 13, *)
    @Test("Check the first write adds the item with its attributes", .timeLimit(.minutes(1)))
    func firstWriteAddsTheItemWithItsAttributes() throws {
        // WHEN
        try sut.write(claimedRecord)

        // THEN
        #expect(keychain.addCallCount == 1)
        #expect(keychain.updateCallCount == 0)
        let attributes = keychain.latestAddAttributes
        expectBaseQuery(attributes)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecAttrAccessGroup as String] == nil)
        #expect(attributes[kSecValueData as String] is Data)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a write over an existing item updates it in place", .timeLimit(.minutes(1)))
    func writeOverAnExistingItemUpdatesItInPlace() throws {
        // GIVEN
        try sut.write(AIChatBonusRecord(dismissed: true))

        // WHEN
        try sut.write(claimedRecord)

        // THEN
        // The second add finds the item and falls back to an update.
        #expect(keychain.addCallCount == 2)
        #expect(keychain.updateCallCount == 1)
        expectBaseQuery(keychain.latestUpdateQuery)
        #expect(keychain.latestUpdateAttributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(try sut.read() == claimedRecord)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check the stored data carries the schema version", .timeLimit(.minutes(1)))
    func storedDataCarriesTheSchemaVersion() throws {
        // WHEN
        try sut.write(claimedRecord)

        // THEN
        let data = try #require(keychain.storedData)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["record"] is [String: Any])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a failed update makes the write throw its status", .timeLimit(.minutes(1)))
    func failedUpdateMakesWriteThrow() {
        // GIVEN
        keychain.storedData = Data()
        keychain.updateStatuses = [errSecInteractionNotAllowed]

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.writeFailed(errSecInteractionNotAllowed)) {
            try sut.write(claimedRecord)
        }
        #expect(keychain.addCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a failed add makes the write throw its status", .timeLimit(.minutes(1)))
    func failedAddMakesWriteThrow() throws {
        // GIVEN
        keychain.addStatus = errSecNotAvailable

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.writeFailed(errSecNotAvailable)) {
            try sut.write(claimedRecord)
        }
        #expect(try sut.read() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a record that breaks the invariant is never written", .timeLimit(.minutes(1)))
    func recordThatBreaksTheInvariantIsNeverWritten() {
        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.invariantViolated) {
            try sut.write(AIChatBonusRecord(bonusId: "id"))
        }
        #expect(keychain.addCallCount == 0)
        #expect(keychain.updateCallCount == 0)
    }

    // MARK: - Delete

    @available(iOS 16, macOS 13, *)
    @Test("Check delete removes the record", .timeLimit(.minutes(1)))
    func deleteRemovesTheRecord() throws {
        // GIVEN
        try sut.write(claimedRecord)
        #expect(try sut.read() != nil)

        // WHEN
        try sut.delete()

        // THEN
        #expect(try sut.read() == nil)
        expectBaseQuery(keychain.latestDeleteQuery)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check deleting a missing record succeeds", .timeLimit(.minutes(1)))
    func deletingAMissingRecordSucceeds() {
        // WHEN / THEN
        #expect(throws: Never.self) {
            try sut.delete()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a failed delete throws its status", .timeLimit(.minutes(1)))
    func failedDeleteThrows() {
        // GIVEN
        keychain.deleteStatus = errSecInteractionNotAllowed

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.deleteFailed(errSecInteractionNotAllowed)) {
            try sut.delete()
        }
    }

    // MARK: - Helpers

    func expectBaseQuery(_ query: [String: Any], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String, sourceLocation: sourceLocation)
        #expect(query[kSecAttrService as String] as? String == serviceName, sourceLocation: sourceLocation)
        #expect(query[kSecAttrAccount as String] as? String == "record", sourceLocation: sourceLocation)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false, sourceLocation: sourceLocation)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true, sourceLocation: sourceLocation)
    }

}
