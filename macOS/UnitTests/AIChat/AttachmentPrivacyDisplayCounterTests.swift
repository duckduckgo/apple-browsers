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

    func testThreeDisplaysAreAllowedAndTheFourthIsNot() {
        let counter = makeCounter()

        XCTAssertTrue(counter.consumeDisplay())
        XCTAssertTrue(counter.consumeDisplay())
        XCTAssertTrue(counter.consumeDisplay())
        XCTAssertFalse(counter.consumeDisplay())
        XCTAssertEqual(counter.displayCount, AttachmentPrivacyDisplayCounter.cap)
    }

    func testCanDisplayFollowsTheCap() {
        let counter = makeCounter()

        XCTAssertTrue(counter.canDisplay)
        counter.consumeDisplay()
        counter.consumeDisplay()
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
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 2

        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, 2)
        XCTAssertTrue(counter.consumeDisplay())
        XCTAssertFalse(counter.consumeDisplay())
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

    func testWebCountAppearingAfterTheTakeoverIsIgnored() {
        _ = makeCounter()

        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 3
        let second = makeCounter()

        XCTAssertEqual(second.displayCount, 0)
        XCTAssertTrue(second.consumeDisplay())
    }

    /// Deliberate: a state handover, not a display, so waiting for the flag risks missing it.
    func testTheTakeoverHappensEvenWithTheFlagOff() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 2

        _ = makeCounter(isEnabled: false)

        XCTAssertEqual(makeCounter().displayCount, 2)
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

        XCTAssertEqual(makeCounter().displayCount, 2)
    }

    // MARK: - Reset

    func testResetClearsTheCount() {
        let counter = makeCounter()
        counter.consumeDisplay()
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

    /// Otherwise the burn re-adopts the web count and the message never comes back.
    func testResetDoesNotLeaveTheWebCountToBeAdoptedAgain() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 3
        let counter = makeCounter()
        counter.reset()

        XCTAssertEqual(makeCounter().displayCount, 0)
    }

    // MARK: -

    private func makeCounter(isEnabled: Bool = true) -> AttachmentPrivacyDisplayCounter {
        AttachmentPrivacyDisplayCounter(
            store: store,
            webKeySource: webStorage,
            featureFlagger: MockFeatureFlagger(
                featuresStub: [FeatureFlag.aiChatAttachmentPrivacyDisclosure.rawValue: isEnabled]
            )
        )
    }
}

final class AttachmentPrivacyCompositionGateTests: XCTestCase {

    private var store: InMemoryAttachmentPrivacyDisplayCountStore!
    private var gate: AttachmentPrivacyCompositionGate!

    override func setUp() {
        super.setUp()
        store = InMemoryAttachmentPrivacyDisplayCountStore()
        gate = AttachmentPrivacyCompositionGate(
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

    func testResolvingRepeatedlyInOneCompositionSpendsOne() {
        for _ in 0..<5 {
            XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        }

        XCTAssertEqual(store.count, 1)
    }

    /// Reported as feeling broken: changing the file mid-flow must not cost a display.
    func testRemovingAndReattachingKeepsTheSameDisplay() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: false, tabID: "A"))

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 1)
    }

    func testANewPromptAfterSubmittingSpendsAnother() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        gate.compositionEnded(tabID: "A")

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 2)
    }

    func testDifferentTabsAreDifferentPrompts() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))

        XCTAssertEqual(store.count, 2)
    }

    func testReturningToATabKeepsItsGrant() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "B")

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertEqual(store.count, 2)
    }

    func testSubmittingInOneTabLeavesAnotherTabsDraftAlone() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "B")

        gate.compositionEnded(tabID: "A")

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))
        XCTAssertEqual(store.count, 2)
    }

    func testASurfaceWithoutATabIsOneComposition() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: nil))
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: nil))

        XCTAssertEqual(store.count, 1)
    }

    func testOnceExhaustedNothingShows() {
        for tab in ["A", "B", "C"] {
            XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: tab))
        }

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "D"))
        XCTAssertEqual(store.count, AttachmentPrivacyDisplayCounter.cap)
    }

    func testADeniedCompositionIsRememberedToo() {
        for tab in ["A", "B", "C"] {
            _ = gate.shouldShow(hasStagedAttachment: true, tabID: tab)
        }

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "D"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "D"))
        XCTAssertEqual(store.count, AttachmentPrivacyDisplayCounter.cap)
    }
}

final class AttachmentPrivacyDisplayCountRegistryTests: XCTestCase {

    func testRegularModeUsesThePersistentStore() {
        let persistent = InMemoryAttachmentPrivacyDisplayCountStore()
        let registry = AttachmentPrivacyDisplayCountRegistry(persistentStore: persistent)

        registry.store(for: .regular).setCount(2)

        XCTAssertEqual(persistent.count, 2)
    }

    func testOneBurnerWindowKeepsOneStore() {
        let registry = AttachmentPrivacyDisplayCountRegistry()
        let mode = BurnerMode(isBurner: true)

        registry.store(for: mode).setCount(2)

        XCTAssertEqual(registry.store(for: mode).count, 2)
    }

    func testBurnerWindowsDoNotShareACount() {
        let registry = AttachmentPrivacyDisplayCountRegistry()

        registry.store(for: BurnerMode(isBurner: true)).setCount(3)

        XCTAssertNil(registry.store(for: BurnerMode(isBurner: true)).count)
    }

    func testABurnerCountIsNotThePersistentOne() {
        let persistent = InMemoryAttachmentPrivacyDisplayCountStore()
        let registry = AttachmentPrivacyDisplayCountRegistry(persistentStore: persistent)

        registry.store(for: BurnerMode(isBurner: true)).setCount(3)

        XCTAssertNil(persistent.count)
    }

    func testResetPersistentLeavesBurnerStoresAlone() {
        let registry = AttachmentPrivacyDisplayCountRegistry()
        let mode = BurnerMode(isBurner: true)
        registry.store(for: .regular).setCount(3)
        registry.store(for: mode).setCount(3)

        registry.resetPersistent()

        XCTAssertNil(registry.store(for: .regular).count)
        XCTAssertEqual(registry.store(for: mode).count, 3)
    }
}

/// Stores entries so the takeover can be driven; the rest is unused.
private final class FakeWebKeyStorage: DuckAiNativeStorageHandling {

    var entries: [String: Any] = [:]

    func putEntry(key: String, value: Any) throws { entries[key] = value }
    func getEntry(key: String) throws -> Any? { entries[key] }
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
