//
//  AttachmentPrivacyDisplayCounterTests.swift
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

import AIChat
import DuckAiDataStore
import FeatureFlags_macOS
import PrivacyConfig
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AttachmentPrivacyDisplayCounterTests: XCTestCase {

    private var store: InMemoryAttachmentPrivacyDisplayCountStore!
    private var webStorage: FakeWebKeyStorage!

    override func setUp() {
        super.setUp()
        store = InMemoryAttachmentPrivacyDisplayCountStore()
        webStorage = FakeWebKeyStorage()
    }

    override func tearDown() {
        store = nil
        webStorage = nil
        super.tearDown()
    }

    // MARK: - The cap

    func testOneDisplayIsAllowedAndTheSecondIsNot() {
        let counter = makeCounter()

        XCTAssertTrue(counter.consumeDisplay())
        XCTAssertFalse(counter.consumeDisplay())
        XCTAssertEqual(counter.displayCount, AttachmentPrivacyDisplayCounter.cap)
    }

    func testCanDisplayFollowsTheCap() {
        let counter = makeCounter()

        XCTAssertTrue(counter.canDisplay)
        counter.consumeDisplay()
        XCTAssertFalse(counter.canDisplay)
    }

    func testCanDisplayDoesNotSpendADisplay() {
        let counter = makeCounter()

        _ = counter.canDisplay
        _ = counter.canDisplay

        XCTAssertEqual(counter.displayCount, 0)
    }

    // MARK: - The kill switch

    func testNothingIsAllowedWithTheFlagOff() {
        let counter = makeCounter(isEnabled: false)

        XCTAssertFalse(counter.canDisplay)
        XCTAssertFalse(counter.consumeDisplay())
        XCTAssertEqual(counter.displayCount, 0)
    }

    // MARK: - Migrating the web app's count

    func testWebCountIsAdopted() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 1

        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, 1)
        XCTAssertFalse(counter.consumeDisplay())
    }

    /// What the web app actually writes: a flag, not a count.
    func testWebFlagIsAdopted() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = true

        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, 1)
        XCTAssertFalse(counter.consumeDisplay())
    }

    func testAnUnsetWebFlagLeavesTheCountAtZero() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = false

        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, 0)
        XCTAssertTrue(counter.consumeDisplay())
    }

    func testWebCountIsCappedWhenAdopted() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 9

        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, AttachmentPrivacyDisplayCounter.cap)
        XCTAssertFalse(counter.consumeDisplay())
    }

    func testWebCountIsAdoptedOnlyOnce() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 1
        _ = makeCounter()

        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 3
        let second = makeCounter()

        XCTAssertEqual(second.displayCount, 1)
    }

    /// Otherwise a counter built before Duck.ai's storage is readable spends the takeover on
    /// nothing, and the message shows again after the web app already showed it.
    func testAFailedReadLeavesTheTakeoverForTheNextCounter() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 1
        webStorage.readError = TestError.unreadable

        XCTAssertEqual(makeCounter().displayCount, 0)

        webStorage.readError = nil
        XCTAssertEqual(makeCounter().displayCount, 1)
    }

    func testAnAbsentStorageHandlerLeavesTheTakeoverForTheNextCounter() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 1

        XCTAssertEqual(makeCounter(webKeySource: nil).displayCount, 0)

        XCTAssertEqual(makeCounter().displayCount, 1)
    }

    func testWebCountAppearingAfterTheTakeoverIsIgnored() {
        _ = makeCounter()

        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 3
        let second = makeCounter()

        XCTAssertEqual(second.displayCount, 0)
        XCTAssertTrue(second.consumeDisplay())
    }

    /// Deliberate: a state handover, not a display, so waiting for the flag risks missing it.
    func testTheTakeoverHappensEvenWithTheFlagOff() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 1

        _ = makeCounter(isEnabled: false)

        XCTAssertEqual(makeCounter().displayCount, 1)
    }

    func testAbsentWebCountLeavesTheCountAtZero() {
        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, 0)
    }

    func testUnreadableWebCountLeavesTheCountAtZero() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = ["unexpected": true]

        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, 0)
        XCTAssertTrue(counter.consumeDisplay())
    }

    func testWebCountIsAdoptedFromAString() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = "2"

        XCTAssertEqual(makeCounter().displayCount, AttachmentPrivacyDisplayCounter.cap)
    }

    // MARK: - Reset

    func testResetClearsTheCount() {
        let counter = makeCounter()
        counter.consumeDisplay()

        counter.reset()

        XCTAssertEqual(counter.displayCount, 0)
        XCTAssertTrue(counter.canDisplay)
    }

    func testResetDeletesTheWebKey() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 2
        let counter = makeCounter()

        counter.reset()

        XCTAssertNil(webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey])
    }

    /// Otherwise the debug reset re-adopts the web count and the message never comes back.
    func testResetDoesNotLeaveTheWebCountToBeAdoptedAgain() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 3
        let counter = makeCounter()
        counter.reset()

        XCTAssertEqual(makeCounter().displayCount, 0)
    }

    // MARK: -

    private func makeCounter(isEnabled: Bool = true) -> AttachmentPrivacyDisplayCounter {
        makeCounter(webKeySource: webStorage, isEnabled: isEnabled)
    }

    private func makeCounter(webKeySource: DuckAiNativeStorageHandling?,
                             isEnabled: Bool = true) -> AttachmentPrivacyDisplayCounter {
        AttachmentPrivacyDisplayCounter(
            store: store,
            webKeySource: webKeySource,
            featureFlagger: MockFeatureFlagger(
                featuresStub: [FeatureFlag.aiChatAttachmentPrivacyDisclosure.rawValue: isEnabled]
            )
        )
    }
}

final class AttachmentPrivacyDisplayGateTests: XCTestCase {

    private var store: InMemoryAttachmentPrivacyDisplayCountStore!
    private var gate: AttachmentPrivacyDisplayGate!

    override func setUp() {
        super.setUp()
        store = InMemoryAttachmentPrivacyDisplayCountStore()
        gate = AttachmentPrivacyDisplayGate(
            counter: AttachmentPrivacyDisplayCounter(
                store: store,
                webKeySource: nil,
                featureFlagger: MockFeatureFlagger(
                    featuresStub: [FeatureFlag.aiChatAttachmentPrivacyDisclosure.rawValue: true]
                )
            )
        )
    }

    override func tearDown() {
        store = nil
        gate = nil
        super.tearDown()
    }

    func testNothingShowsWithoutAnAttachment() {
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: false, tabID: "A"))
        XCTAssertNil(store.count)
    }

    func testStagingAnAttachmentSpendsOneDisplay() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 1)
    }

    func testResolvingRepeatedlyWhileStagedSpendsOne() {
        for _ in 0..<5 {
            XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        }

        XCTAssertEqual(store.count, 1)
    }

    /// Emptying the attachments ends the display, and the one display is already spent.
    func testRemovingAndReattachingDoesNotShowAgain() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: false, tabID: "A"))

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 1)
    }

    func testAttachingAgainAfterSubmittingDoesNotShowAgain() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        gate.displayEnded(tabID: "A")

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 1)
    }

    func testOnlyOneTabGetsTheDisplay() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))

        XCTAssertEqual(store.count, 1)
    }

    func testReturningToATabKeepsItsGrant() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "B")

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 1)
    }

    func testSubmittingInOneTabLeavesAnotherTabsDisplayAlone() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")

        gate.displayEnded(tabID: "B")

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 1)
    }

    func testASurfaceWithoutATabIsOneDisplay() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: nil))
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: nil))

        XCTAssertEqual(store.count, 1)
    }

    func testADeniedDisplayIsRememberedWhileStaged() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))
        XCTAssertEqual(store.count, AttachmentPrivacyDisplayCounter.cap)
    }
}

private enum TestError: Error {
    case unreadable
}

/// Stores entries so the takeover can be driven; the rest is unused.
private final class FakeWebKeyStorage: DuckAiNativeStorageHandling {

    var entries: [String: Any] = [:]
    var readError: Error?

    func putEntry(key: String, value: Any) throws { entries[key] = value }

    func getEntry(key: String) throws -> Any? {
        if let readError { throw readError }
        return entries[key]
    }
    func getAllEntries() throws -> [String: Any] { entries }
    func deleteEntry(key: String) throws { entries.removeValue(forKey: key) }
    func deleteAllEntries() throws { entries.removeAll() }
    func replaceAllEntries(_ entries: [String: Any]) throws { self.entries = entries }

    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? { nil }
    func getAllChats() throws -> [DuckAiChatRecord] { [] }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { false }
    func isMigrationDone(key: String) throws -> Bool { false }
    func markMigrationDone(key: String) throws {}
}
