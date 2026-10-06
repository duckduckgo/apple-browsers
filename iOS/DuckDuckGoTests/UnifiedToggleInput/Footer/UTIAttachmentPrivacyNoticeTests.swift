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
    private var kind: UTIAttachmentPrivacyKind? = .image
    private var enabled = true

    override func setUp() {
        super.setUp()
        storage = AttachmentPrivacyTestStore()
        store = UTIAttachmentPrivacyNoticeDisplayStore(keyValueStore: storage)
        kind = .image
        enabled = true
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
                                              displayStore: store)
    }

    func testAttachShowsAndSetsFlagThenNextPromptDoesNotShow() {
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertTrue(source.recordDisplay())
        XCTAssertTrue(store.hasShown)

        kind = nil
        source.refresh()
        source.clear()
        kind = .image
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
    }

    func testAttachRemoveAttachShowsOnceAndSetsFlag() {
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        kind = nil
        source.refresh()
        XCTAssertFalse(source.isPresented)
        kind = .file
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
        XCTAssertTrue(store.hasShown)
    }

    func testDisplayStaysUntilItEndsAndIsRecordedOnce() {
        source.refresh()
        XCTAssertTrue(source.recordDisplay())
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
        XCTAssertEqual(storage.writeCount, 1)
        source.endDisplay()
        source.refresh()
        XCTAssertFalse(source.isPresented)
    }

    func testDisplayInFireTabSetsFlagSoNormalTabDoesNotShow() {
        let fireTabSource = makeSource()
        fireTabSource.refresh()
        XCTAssertTrue(fireTabSource.recordDisplay())
        XCTAssertTrue(store.hasShown)

        let normalTabSource = makeSource()
        normalTabSource.refresh()
        XCTAssertFalse(normalTabSource.isPresented)
        XCTAssertFalse(normalTabSource.recordDisplay())
    }

    func testResolvingWithoutDisplayingDoesNotSetFlag() {
        source.refresh()
        source.refresh()
        XCTAssertTrue(source.isPresented)
        XCTAssertFalse(store.hasShown)
    }

    func testFlagOffAndMissingAttachmentDoNotShowOrSetFlag() {
        enabled = false
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
        enabled = true
        kind = nil
        source.refresh()
        XCTAssertFalse(source.isPresented)
        XCTAssertFalse(source.recordDisplay())
        XCTAssertFalse(store.hasShown)
    }

    func testFlagRoundTripsAcrossStoreInstances() {
        store.markShown()
        let reloaded = UTIAttachmentPrivacyNoticeDisplayStore(keyValueStore: storage)
        XCTAssertTrue(reloaded.hasShown)
        reloaded.reset()
        XCTAssertFalse(UTIAttachmentPrivacyNoticeDisplayStore(keyValueStore: storage).hasShown)
    }

    func testInvalidOrFailingStorageReadsAsNotShown() {
        storage.overrideRead = "not a flag"
        XCTAssertFalse(store.hasShown)
        storage.overrideRead = 1
        XCTAssertFalse(store.hasShown)
        storage.overrideRead = nil
        storage.failReads = true
        source.refresh()
        XCTAssertTrue(source.isPresented)
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
