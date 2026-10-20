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

import Combine
import Foundation
import Testing
@testable import AIChat

@Suite("AIChatBonus - Service Tests")
struct AIChatBonusServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_780_000_000.123_4)

    private static let expired = AIChatBonusRecord(
        campaignName: AIChatBonusRecordMock.campaignName,
        bonusId: AIChatBonusRecordMock.bonusId,
        terms: AIChatBonusRecord.Terms(multiplier: 2, expiresAt: now.timeIntervalSince1970 - 1),
        lastRedeemAttemptAt: 1_770_000_000_000
    )

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

    // MARK: - Boost state

    @Test("Check the boost is active with an unexpired record stored")
    func boostIsActiveWithAnUnexpiredRecord() throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.active
        let beforeExpiry = Date(timeIntervalSince1970: AIChatBonusRecordMock.terms.expiresAt - 1)

        // WHEN
        let result = try sut.isBoostActive(at: beforeExpiry)

        // THEN
        #expect(result)
    }

    @Test("Check the boost isn't active without a record")
    func boostIsNotActiveWithoutARecord() throws {
        // WHEN
        let result = try sut.isBoostActive()

        // THEN
        #expect(!result)
    }

    @Test("Check the boost state throws when the record can't be read")
    func boostStateThrowsWhenTheReadFails() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) {
            try sut.isBoostActive()
        }
    }

    // MARK: - Record publisher

    @available(iOS 16, macOS 13, *)
    @Test("Check a claim publishes the claimed record", .timeLimit(.minutes(1)))
    func claimPublishesTheRecord() async throws {
        // GIVEN
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        let result = try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)

        // THEN
        await drainMainQueue()
        #expect(published.values == [result])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a claim on an already claimed record publishes nothing", .timeLimit(.minutes(1)))
    func claimOnClaimedRecordPublishesNothing() async throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.pending
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        _ = try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)

        // THEN
        await drainMainQueue()
        #expect(published.values.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a repeated change publishes only once", .timeLimit(.minutes(1)))
    func repeatedChangePublishesOnlyOnce() async throws {
        // GIVEN
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        try sut.dismiss()
        try sut.dismiss()

        // THEN
        await drainMainQueue()
        #expect(published.values == [AIChatBonusRecord(dismissed: true)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check ending an already ended boost publishes nothing", .timeLimit(.minutes(1)))
    func endingAnEndedBoostPublishesNothing() async throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.ended
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        try sut.end()

        // THEN
        await drainMainQueue()
        #expect(published.values.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check reading the record publishes nothing", .timeLimit(.minutes(1)))
    func readingPublishesNothing() async throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.active
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        _ = try sut.record()

        // THEN
        await drainMainQueue()
        #expect(published.values.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a failed write publishes nothing", .timeLimit(.minutes(1)))
    func failedWritePublishesNothing() async {
        // GIVEN
        store.writeError = AIChatBonusStoreError.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        try? sut.dismiss()

        // THEN
        await drainMainQueue()
        #expect(published.values.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check the next change publishes after a failed write", .timeLimit(.minutes(1)))
    func nextChangePublishesAfterAFailedWrite() async throws {
        // GIVEN
        store.writeError = AIChatBonusStoreError.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        #expect(throws: AIChatBonusStoreError.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)) {
            try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)
        }
        store.writeError = nil
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        try sut.dismiss()

        // THEN
        await drainMainQueue()
        #expect(published.values == [AIChatBonusRecord(dismissed: true)])
    }

    // Must run off main: main has to stay free to deliver the record while this thread waits.
    @Test("Check a subscriber that reads the record when notified doesn't deadlock")
    func subscriberReadingTheRecordDoesNotDeadlock() {
        // GIVEN
        // Signalled once the subscriber has finished, even if that happens before the wait below.
        let readFinished = DispatchSemaphore(value: 0)
        var recordReadBySubscriber: AIChatBonusRecord?
        // Subscribed before the write: the publisher doesn't replay. Calling back into the service is the case that could deadlock.
        let cancellable = sut.recordPublisher.sink { [sut] _ in
            recordReadBySubscriber = try? sut.record()
            readFinished.signal()
        }

        // WHEN
        // Write on another thread so a regressed subscriber can't run, and deadlock, on the test thread: the wait below fails instead of hanging.
        DispatchQueue.global().async { [sut] in
            try? sut.dismiss()
        }

        // THEN
        #expect(readFinished.wait(timeout: .now() + 5) == .success)
        #expect(recordReadBySubscriber == AIChatBonusRecord(dismissed: true))
        cancellable.cancel()
    }

    // MARK: - Expired boost

    @Test("Check reading an expired boost ends it and keeps the campaign")
    func readingAnExpiredBoostEndsIt() throws {
        // GIVEN
        store.storedRecord = Self.expired

        // WHEN
        let result = try sut.record()

        // THEN
        #expect(result == AIChatBonusRecordMock.ended)
        #expect(store.storedRecord == AIChatBonusRecordMock.ended)
    }

    @Test("Check reading an unexpired boost leaves it as it is")
    func readingAnUnexpiredBoostLeavesIt() throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.active

        // WHEN
        let result = try sut.record()

        // THEN
        #expect(result == AIChatBonusRecordMock.active)
        #expect(store.writeCallCount == 0)
    }

    @Test("Check reading a pending claim leaves it as it is")
    func readingAPendingClaimLeavesIt() throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.pending

        // WHEN
        let result = try sut.record()

        // THEN
        #expect(result == AIChatBonusRecordMock.pending)
        #expect(store.writeCallCount == 0)
    }

    @Test("Check the boost isn't active once an expired record is ended")
    func expiredBoostIsNotActive() throws {
        // GIVEN
        store.storedRecord = Self.expired

        // WHEN
        let result = try sut.isBoostActive()

        // THEN
        #expect(!result)
        #expect(store.storedRecord == AIChatBonusRecordMock.ended)
    }

    @Test("Check ending an expired boost ends it")
    func endBoostIfExpiredEndsAnExpiredBoost() throws {
        // GIVEN
        store.storedRecord = Self.expired

        // WHEN
        try sut.endBoostIfExpired()

        // THEN
        #expect(store.storedRecord == AIChatBonusRecordMock.ended)
    }

    @Test("Check a failed write while ending an expired boost still returns the record")
    func failedExpiryWriteStillReturnsTheRecord() throws {
        // GIVEN
        store.storedRecord = Self.expired
        store.writeError = AIChatBonusStoreError.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)

        // WHEN
        let result = try sut.record()

        // THEN
        #expect(result == Self.expired)
        #expect(pixelFiring.storeFailures == [.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check ending an expired boost publishes the ended record", .timeLimit(.minutes(1)))
    func endingAnExpiredBoostPublishes() async throws {
        // GIVEN
        store.storedRecord = Self.expired
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        _ = try sut.record()

        // THEN
        await drainMainQueue()
        #expect(published.values == [AIChatBonusRecordMock.ended])
    }

    @Test("Check a failed read while ending an expired boost is passed on")
    func failedReadWhileEndingAnExpiredBoostIsPassedOn() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) {
            try sut.endBoostIfExpired()
        }
    }

    // MARK: - Permanent delete

    @Test("Check deleting the record permanently removes it")
    func permanentlyDeletingRemovesTheRecord() throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.active

        // WHEN
        try sut.permanentlyDeleteRecord()

        // THEN
        #expect(store.storedRecord == nil)
        #expect(try sut.record() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check deleting the record permanently publishes nothing", .timeLimit(.minutes(1)))
    func permanentlyDeletingPublishesNothing() async throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.active
        let published = PublishedValues(sut.recordPublisher)

        // WHEN
        try sut.permanentlyDeleteRecord()

        // THEN
        await drainMainQueue()
        #expect(published.values.isEmpty)
    }

    @Test("Check a failed delete is retried on the next read")
    func failedDeleteIsRetriedOnTheNextRead() throws {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.active
        store.deleteError = AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) {
            try sut.permanentlyDeleteRecord()
        }
        store.deleteError = nil

        // WHEN
        let result = try sut.record()

        // THEN
        #expect(result == nil)
        #expect(store.deleteCallCount == 2)
        #expect(pixelFiring.storeFailures == [.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)])
    }

    @Test("Check the old record is never returned while the delete keeps failing")
    func oldRecordIsNotReturnedWhileTheDeleteFails() {
        // GIVEN
        store.storedRecord = AIChatBonusRecordMock.active
        store.deleteError = AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) {
            try sut.permanentlyDeleteRecord()
        }

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) {
            try sut.record()
        }
        #expect(store.readCallCount == 0)
    }

    @Test("Check a claim mints nothing while a failed delete keeps failing")
    func claimMintsNothingWhileTheDeleteFails() {
        // GIVEN: a previous install's record is left behind because the delete failed, and it keeps failing.
        store.storedRecord = AIChatBonusRecordMock.ended
        store.deleteError = AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) {
            try sut.permanentlyDeleteRecord()
        }

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) {
            try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)
        }
        #expect(store.writeCallCount == 0)
        #expect(store.storedRecord == AIChatBonusRecordMock.ended)
    }

    @Test("Check a claim retries a failed delete before reading the record")
    func claimRetriesAFailedDeleteFirst() throws {
        // GIVEN: a previous install's ended record is left behind because the delete failed.
        store.storedRecord = AIChatBonusRecordMock.ended
        store.deleteError = AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) {
            try sut.permanentlyDeleteRecord()
        }
        store.deleteError = nil

        // WHEN
        let result = try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)

        // THEN: the old record is gone, so a new Bonus ID is minted.
        #expect(store.deleteCallCount == 2)
        #expect(result == AIChatBonusRecord(campaignName: AIChatBonusRecordMock.campaignName, bonusId: AIChatBonusRecordMock.bonusId))
    }

    @Test("Check a successful retry isn't repeated on later reads")
    func successfulRetryIsNotRepeated() throws {
        // GIVEN
        store.deleteError = AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) {
            try sut.permanentlyDeleteRecord()
        }
        store.deleteError = nil
        _ = try sut.record()

        // WHEN
        let result = try sut.record()

        // THEN
        #expect(store.deleteCallCount == 2)
        #expect(result == nil)
    }

    // MARK: - Failures

    @Test("Check a failed read stops a claim before any write")
    func failedReadStopsTheClaim() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) {
            try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)])
    }

    @Test("Check a failed read stops a redeem outcome before any write")
    func failedReadStopsTheRedeemOutcome() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) {
            try sut.applyRedeemOutcome(.success(bonusId: AIChatBonusRecordMock.bonusId, terms: AIChatBonusRecordMock.terms))
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)])
    }

    @Test("Check a failed read stops a dismiss before any write")
    func failedReadStopsTheDismiss() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) {
            try sut.dismiss()
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)])
    }

    @Test("Check a failed read stops an end before any write")
    func failedReadStopsTheEnd() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) {
            try sut.end()
        }
        #expect(store.writeCallCount == 0)
        #expect(pixelFiring.storeFailures == [.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)])
    }

    @Test("Check a failed read of the record is reported")
    func failedRecordReadIsReported() {
        // GIVEN
        store.readError = AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) {
            try sut.record()
        }
        #expect(pixelFiring.storeFailures == [.readFailed(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)])
    }

    @Test("Check a failed write is passed on")
    func failedWriteIsPassedOn() {
        // GIVEN
        store.writeError = AIChatBonusStoreError.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)) {
            try sut.claim(campaignName: AIChatBonusRecordMock.campaignName)
        }
        #expect(store.storedRecord == nil)
        #expect(pixelFiring.storeFailures == [.writeFailed(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)])
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
