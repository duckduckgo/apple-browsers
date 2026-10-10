//
//  AIChatBonusServiceTests.swift
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

@Suite("AIChatBonus - Service Tests")
struct AIChatBonusServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_780_000_000.123_4)

    private let store = MockAIChatBonusStore()
    private let pixelFiring = MockAIChatBonusPixelFiring()
    private let sut: AIChatBonusService

    init() {
        sut = AIChatBonusService(
            store: store,
            pixelFiring: pixelFiring,
            now: { Self.now },
            makeBonusId: { AIChatBonusRecordMock.bonusId }
        )
    }

    // MARK: - Record

    @Test("Check record returns the stored record")
    func recordReturnsTheStoredRecord() throws {
        // GIVEN
        let record = AIChatBonusRecordMock.pending
        store.storedRecord = record

        // WHEN
        let result = try sut.record()

        // THEN
        #expect(result == record)
    }

    // MARK: - Claim

    @Test("Check a claim stores and returns the minted record")
    func claimStoresTheMintedRecord() throws {
        // GIVEN
        let campaignName = AIChatBonusRecordMock.campaignName
        let expected = AIChatBonusRecord(campaignName: campaignName, bonusId: AIChatBonusRecordMock.bonusId)

        // WHEN
        let result = try sut.claim(campaignName: campaignName)

        // THEN
        #expect(result == expected)
        #expect(store.storedRecord == expected)
        #expect(store.writeCallCount == 1)
    }

    @Test("Check a second claim returns the stored record without writing")
    func secondClaimReturnsTheStoredRecord() throws {
        // GIVEN
        let first = try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)

        // WHEN
        let second = try sut.claim(campaignName: "other")

        // THEN
        #expect(second == first)
        #expect(store.writeCallCount == 1)
    }

    @Test("Check a default Bonus ID is a lowercase UUID")
    func defaultBonusIdIsALowercaseUUID() throws {
        // GIVEN
        let sut = AIChatBonusService(store: store)

        // WHEN
        let bonusId = try #require(try sut.claim(campaignName: AIChatBonusRecordMock.campaignName).bonusId)

        // THEN
        #expect(UUID(uuidString: bonusId) != nil)
        #expect(bonusId == bonusId.lowercased())
    }

    @Test("Check concurrent claims store exactly one Bonus ID")
    func concurrentClaimsStoreOneBonusId() {
        // GIVEN
        // The default mints a new UUID on every claim, so a second write would show up as a second ID.
        let sut = AIChatBonusService(store: store)
        let results = ResultsBox()

        // WHEN
        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            results.append(try? sut.claim(campaignName: AIChatBonusRecordMock.campaignName).bonusId)
        }

        // THEN
        #expect(store.writeCallCount == 1)
        #expect(results.values.count == 50)
        #expect(Set(results.values) == [store.storedRecord?.bonusId])
    }

    // MARK: - Redeem outcome

    @Test("Check a redeem success stores the terms with the attempt time in milliseconds")
    func redeemSuccessStoresTerms() throws {
        // GIVEN
        let record = AIChatBonusRecordMock.pending
        let terms = AIChatBonusRecordMock.terms
        store.storedRecord = record
        #expect(store.storedRecord?.terms == nil)
        let expected = record.with {
            $0.terms = terms
            $0.lastRedeemAttemptAt = Self.now.timeIntervalSince1970 * 1000 // in milliseconds
        }

        // WHEN
        try sut.applyRedeemOutcome(.success(bonusId: AIChatBonusRecordMock.bonusId, terms: terms))

        // THEN
        #expect(store.storedRecord == expected)
    }

    @Test("Check a redeem outcome for another Bonus ID writes nothing")
    func redeemOutcomeForAnotherBonusIdWritesNothing() throws {
        // GIVEN
        let record = AIChatBonusRecordMock.pending
        store.storedRecord = record
        #expect(store.storedRecord?.bonusId != AIChatBonusRecordMock.otherBonusId)

        // WHEN
        try sut.applyRedeemOutcome(.success(bonusId: AIChatBonusRecordMock.otherBonusId, terms: AIChatBonusRecordMock.terms))

        // THEN
        #expect(store.storedRecord == record)
        #expect(store.writeCallCount == 0)
    }

    // MARK: - Dismiss and end

    @Test("Check a dismiss is stored")
    func dismissIsStored() throws {
        // WHEN
        try sut.dismiss()

        // THEN
        #expect(store.storedRecord == AIChatBonusRecord(dismissed: true))
    }

    @Test("Check a repeated dismiss writes nothing")
    func repeatedDismissWritesNothing() throws {
        // GIVEN
        try sut.dismiss()

        // WHEN
        try sut.dismiss()

        // THEN
        #expect(store.storedRecord == AIChatBonusRecord(dismissed: true))
        #expect(store.writeCallCount == 1)
    }

    @Test("Check an end keeps only the campaign")
    func endKeepsOnlyTheCampaign() throws {
        // GIVEN
        let record = AIChatBonusRecordMock.active.with { $0.dismissed = true }
        store.storedRecord = record

        // WHEN
        try sut.end()

        // THEN
        #expect(store.storedRecord == AIChatBonusRecord(campaignName: record.campaignName))
    }

    @Test("Check an end with no Bonus ID writes nothing")
    func endWithNoBonusIdWritesNothing() throws {
        // GIVEN
        let record = AIChatBonusRecordMock.ended
        store.storedRecord = record

        // WHEN
        try sut.end()

        // THEN
        #expect(store.storedRecord == record)
        #expect(store.writeCallCount == 0)
    }

    // MARK: - Failures

    @Test("Check a failed read stops a claim before any write")
    func failedReadStopsTheClaim() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)) {
            try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(errSecInteractionNotAllowed)])
    }

    @Test("Check a failed read stops a redeem outcome before any write")
    func failedReadStopsTheRedeemOutcome() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)) {
            try sut.applyRedeemOutcome(.success(bonusId: AIChatBonusRecordMock.bonusId, terms: AIChatBonusRecordMock.terms))
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(errSecInteractionNotAllowed)])
    }

    @Test("Check a failed read stops a dismiss before any write")
    func failedReadStopsTheDismiss() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)) {
            try sut.dismiss()
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(errSecInteractionNotAllowed)])
    }

    @Test("Check a failed read stops an end before any write")
    func failedReadStopsTheEnd() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)) {
            try sut.end()
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(errSecInteractionNotAllowed)])
    }

    @Test("Check a failed read of the record is reported")
    func failedRecordReadIsReported() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(errSecInteractionNotAllowed)) {
            try sut.record()
        }
        #expect(pixelFiring.storeFailures == [.readFailed(errSecInteractionNotAllowed)])
    }

    @Test("Check a failed write is passed on")
    func failedWriteIsPassedOn() {
        // GIVEN
        store.writeError = AIChatBonusStoreError.writeFailed(errSecNotAvailable)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.writeFailed(errSecNotAvailable)) {
            try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)
        }
        #expect(store.storedRecord == nil)
        #expect(pixelFiring.storeFailures == [.writeFailed(errSecNotAvailable)])
    }
}

// MARK: - Helpers

extension AIChatBonusServiceTests {

    final class ResultsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String?] = []

        var values: [String?] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ value: String?) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(value)
        }
    }
}
