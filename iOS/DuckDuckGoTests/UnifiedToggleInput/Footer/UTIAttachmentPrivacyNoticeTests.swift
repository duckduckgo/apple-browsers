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
    private var store: UTIAttachmentPrivacyNoticeDisplayStore!
    private var source: UTIFooterAttachmentPrivacyNoticeSource!
    private var kind: AttachmentPrivacyPixel.Kind? = .image
    private var enabled = true
    private var scope: UTIFooterAttachmentPrivacyNoticeSource.DisplayScope = .normal

    override func setUp() {
        super.setUp()
        storage = AttachmentPrivacyTestStore()
        store = UTIAttachmentPrivacyNoticeDisplayStore(keyValueStore: storage)
        kind = .image
        enabled = true
        scope = .normal
        source = makeSource()
    }

    override func tearDown() {
        source = nil
        store = nil
        storage = nil
        super.tearDown()
    }

    private func makeSource() -> UTIFooterAttachmentPrivacyNoticeSource {
        UTIFooterAttachmentPrivacyNoticeSource(attachmentKind: { [unowned self] in kind },
                                              isEnabled: { [unowned self] in enabled },
                                              displayScope: { [unowned self] in scope },
                                              displayStore: store)
    }

    private func displayAndEnd() {
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        source.endDisplay()
    }

    func testResolvingWithoutDisplayingDoesNotCount() {
        source.refresh()
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertEqual(store.displayCount, 0)
    }

    func testCountRoundTripsAcrossStoreInstances() {
        store.recordDisplay()
        let reloaded = UTIAttachmentPrivacyNoticeDisplayStore(keyValueStore: storage)
        XCTAssertEqual(reloaded.displayCount, 1)
    }

    func testThirdDisplayStaysVisibleUntilItEndsThenCapApplies() {
        for _ in 0..<2 { displayAndEnd() }
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        XCTAssertEqual(store.displayCount, 3)
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
        source.endDisplay()
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
    }

    func testAttachmentRemovalEndsThirdDisplay() {
        for _ in 0..<2 { displayAndEnd() }
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        kind = nil
        source.refresh()
        kind = .file
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertEqual(store.displayCount, 3)
    }

    func testRecreatedSourceHonoursCap() {
        for _ in 0..<3 { displayAndEnd() }
        let reopened = makeSource()
        reopened.refresh()
        XCTAssertFalse(reopened.isPresented)
    }

    func testRepeatedDisplayCallbackAndRefreshDoNotIncrementAgain() {
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        source.refresh()
        XCTAssertFalse(source.recordDisplay())
        XCTAssertEqual(store.displayCount, 1)
    }

    func testResetAllowsAnotherDisplay() {
        for _ in 0..<3 { displayAndEnd() }
        store.reset()
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertEqual(store.displayCount, 0)
    }

    func testInvalidAndNegativeStorageDefaultsToZero() {
        storage.overrideRead = "not a count"
        XCTAssertEqual(store.displayCount, 0)
        storage.overrideRead = -1
        XCTAssertEqual(store.displayCount, 0)
        storage.failReads = true
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testStoreDoesNotOverflowOrIncrementBeyondCap() {
        storage.overrideRead = Int.max
        store.recordDisplay()
        XCTAssertEqual(storage.writeCount, 0)
        source.refresh()
        XCTAssertFalse(source.isPresented)
    }

    func testFlagOffAndMissingAttachmentDoNotCount() {
        enabled = false
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
        enabled = true
        kind = nil
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
        kind = .file
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertEqual(store.displayCount, 0)
    }

    func testFireTabIgnoresPersistentCapWithoutReadingIt() {
        for _ in 0..<3 { store.recordDisplay() }
        storage.readCount = 0
        scope = .fireTab(Tab(fireTab: true))
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(storage.writeCount, 3)
    }

    func testFireDisplaysNeverReadOrWritePersistentStorage() {
        let tab = Tab(fireTab: true)
        scope = .fireTab(tab)
        for _ in 0..<3 { displayAndEnd() }
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertEqual(tab.attachmentPrivacyNoticeDisplayCount, 3)
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(storage.writeCount, 0)
        scope = .normal
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertEqual(store.displayCount, 0)
    }

    func testFireCountSurvivesSourceRecreationButNewTabStartsFresh() {
        let tab = Tab(fireTab: true)
        scope = .fireTab(tab)
        for _ in 0..<3 { displayAndEnd() }
        source = makeSource()
        source.refresh()
        XCTAssertFalse(source.isPresented)
        scope = .fireTab(Tab(fireTab: true))
        source.refresh()
        XCTAssertTrue(source.isPresented)
        scope = .fireTab(tab)
        source.refresh()
        XCTAssertFalse(source.isPresented)
    }

    func testScopeChangeCannotReuseVisibleThirdDisplay() {
        scope = .fireTab(Tab(fireTab: true))
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        for _ in 0..<3 { store.recordDisplay() }
        scope = .normal
        source.refresh()
        XCTAssertFalse(source.isPresented)
    }

    func testMissingFireTabNeverFallsBackToPersistentStorage() {
        scope = .fireTab(nil)
        displayAndEnd()
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(storage.writeCount, 0)
    }

    func testNormalBurnClearsPersistentCount() async {
        for _ in 0..<3 { store.recordDisplay() }
        await AttachmentPrivacyNoticeFireWorker(displayStore: store).burnNormalModeData()
        XCTAssertEqual(store.displayCount, 0)
        source.refresh()
        XCTAssertTrue(source.isPresented)
    }

    func testFireModeBurnClearsPersistentCountWithoutChangingSurvivingTab() async {
        store.recordDisplay()
        let tab = Tab(fireTab: true)
        scope = .fireTab(tab)
        displayAndEnd()
        await AttachmentPrivacyNoticeFireWorker(displayStore: store).burnFireModeData()
        XCTAssertEqual(store.displayCount, 0)
        XCTAssertEqual(tab.attachmentPrivacyNoticeDisplayCount, 1)
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
