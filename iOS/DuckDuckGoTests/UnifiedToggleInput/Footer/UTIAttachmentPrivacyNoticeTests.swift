//
//  UTIAttachmentPrivacyNoticeTests.swift
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

import Persistence
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIAttachmentPrivacyNoticeTests: XCTestCase {

    private var storage: AttachmentPrivacyTestStore!
    private var store: UTIAttachmentPrivacyNoticeDismissalStore!
    private var source: UTIFooterAttachmentPrivacyNoticeSource!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var kind: AttachmentPrivacyPixel.Kind? = .image
    private var enabled = true
    private var scope: UTIFooterAttachmentPrivacyNoticeSource.DismissalScope = .normal

    override func setUp() {
        super.setUp()
        storage = AttachmentPrivacyTestStore()
        store = UTIAttachmentPrivacyNoticeDismissalStore(keyValueStore: storage)
        now = Date(timeIntervalSince1970: 1_800_000_000)
        kind = .image
        enabled = true
        scope = .normal
        source = UTIFooterAttachmentPrivacyNoticeSource(
            attachmentKind: { [unowned self] in kind },
            isEnabled: { [unowned self] in enabled },
            dismissalScope: { [unowned self] in scope },
            dismissalStore: store,
            dateProvider: { [unowned self] in now })
    }

    override func tearDown() {
        source = nil
        store = nil
        storage = nil
        super.tearDown()
    }

    func testNeverDismissedShowsValidAttachment() {
        source.refresh()
        XCTAssertNil(store.dismissedAt)
        XCTAssertTrue(source.isPresented)
    }

    func testDismissalRoundTripsAcrossStoreInstances() {
        store.recordDismissal(at: now)
        let reloaded = UTIAttachmentPrivacyNoticeDismissalStore(keyValueStore: storage)
        XCTAssertEqual(reloaded.dismissedAt, now)
    }

    func testDismissalSuppressesUntilExactlyTwentyOneDays() {
        source.dismissCurrent()
        now += 21 * 24 * 60 * 60 - 1
        source.refresh()
        XCTAssertFalse(source.isPresented)

        now += 1
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testExpiredDismissalShowsAgain() {
        store.recordDismissal(at: now.addingTimeInterval(-22 * 24 * 60 * 60))
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testClearingDismissalShowsAgain() {
        source.dismissCurrent()
        store.clearDismissal()
        source.refresh()
        XCTAssertNil(store.dismissedAt)
        XCTAssertTrue(source.isPresented)
    }

    func testUnreadableStorageShowsAgain() {
        store.recordDismissal(at: now)
        storage.overrideRead = "not a date"
        source.refresh()
        XCTAssertNil(store.dismissedAt)
        XCTAssertTrue(source.isPresented)
    }

    func testStorageReadFailureShowsAgain() {
        store.recordDismissal(at: now)
        storage.failReads = true
        source.refresh()
        XCTAssertNil(store.dismissedAt)
        XCTAssertTrue(source.isPresented)
    }

    func testFlagChangesAreReadOnRefresh() {
        source.refresh()
        XCTAssertTrue(source.isPresented)
        enabled = false
        source.refresh()
        XCTAssertFalse(source.isPresented)
        enabled = true
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testNoValidAttachmentDoesNotShow() {
        kind = nil
        source.refresh()
        XCTAssertFalse(source.isPresented)
    }

    func testTeardownDoesNotRecordDismissal() {
        source.refresh()
        source.clear()
        XCTAssertFalse(source.isPresented)
        XCTAssertNil(store.dismissedAt)
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testFireTabIgnoresNormalDismissalWithoutReadingPersistentStore() {
        store.recordDismissal(at: now)
        scope = .fireTab(Tab(fireTab: true))
        source.refresh()

        XCTAssertTrue(source.isPresented)
        XCTAssertEqual(storage.readCount, 0)
    }

    func testFireDismissalNeverWritesToPersistentStoreOrSuppressesNormalTabs() {
        let tab = Tab(fireTab: true)
        scope = .fireTab(tab)
        source.refresh()
        source.dismissCurrent()
        source.refresh()

        XCTAssertFalse(source.isPresented)
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(storage.writeCount, 0)
        XCTAssertTrue(storage.values.isEmpty)
        scope = .normal
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testFireDismissalPreservesExistingNormalDismissal() {
        store.recordDismissal(at: now)
        scope = .fireTab(Tab(fireTab: true))
        source.dismissCurrent()

        XCTAssertEqual(storage.writeCount, 1)
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(store.dismissedAt, now)
        scope = .normal
        source.refresh()
        XCTAssertFalse(source.isPresented)
    }

    func testFireDismissalSurvivesReopeningAndDoesNotExpireWithinSameTab() {
        let tab = Tab(fireTab: true)
        scope = .fireTab(tab)
        source.dismissCurrent()
        source.clear()
        now += 22 * 24 * 60 * 60
        let reopened = UTIFooterAttachmentPrivacyNoticeSource(
            attachmentKind: { .file },
            isEnabled: { true },
            dismissalScope: { .fireTab(tab) },
            dismissalStore: store,
            dateProvider: { [unowned self] in now })
        reopened.refresh()

        XCTAssertFalse(reopened.isPresented)
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(storage.writeCount, 0)
    }

    func testNewFireTabShowsNoticeAndReturningToDismissedTabKeepsItHidden() {
        let first = Tab(fireTab: true)
        scope = .fireTab(first)
        source.dismissCurrent()
        scope = .fireTab(Tab(fireTab: true))
        source.refresh()
        XCTAssertTrue(source.isPresented)
        scope = .fireTab(first)
        source.refresh()
        XCTAssertFalse(source.isPresented)
    }

    func testMissingFireTabNeverFallsBackToPersistentStore() {
        scope = .fireTab(nil)
        source.refresh()
        source.dismissCurrent()
        source.refresh()

        XCTAssertTrue(source.isPresented)
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(storage.writeCount, 0)
    }

    func testBurnClearsNormalDismissalWithoutResettingSurvivingFireTabSession() async {
        store.recordDismissal(at: now)
        let tab = Tab(fireTab: true)
        scope = .fireTab(tab)
        source.dismissCurrent()

        await AttachmentPrivacyNoticeFireWorker(dismissalStore: store).burnFireModeData()

        XCTAssertNil(store.dismissedAt)
        source.refresh()
        XCTAssertFalse(source.isPresented)
        scope = .fireTab(Tab(fireTab: true))
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testNormalBurnClearsPersistedDismissal() async {
        store.recordDismissal(at: now)
        let worker = AttachmentPrivacyNoticeFireWorker(dismissalStore: store)
        await worker.burnNormalModeData()
        XCTAssertNil(store.dismissedAt)
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testFireModeBurnClearsPersistedDismissal() async {
        store.recordDismissal(at: now)
        let worker = AttachmentPrivacyNoticeFireWorker(dismissalStore: store)
        await worker.burnFireModeData()
        XCTAssertNil(store.dismissedAt)
    }
}

private final class AttachmentPrivacyTestStore: ThrowingKeyValueStoring {
    var values: [String: Any] = [:]
    var overrideRead: Any?
    var failReads = false
    var readCount = 0
    var writeCount = 0

    func object(forKey key: String) throws -> Any? {
        readCount += 1
        if failReads { throw NSError(domain: "test", code: 1) }
        return overrideRead ?? values[key]
    }

    func set(_ value: Any?, forKey key: String) throws {
        writeCount += 1
        values[key] = value
    }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}
