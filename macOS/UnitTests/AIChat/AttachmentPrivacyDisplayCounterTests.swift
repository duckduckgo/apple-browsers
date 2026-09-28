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

    /// A read must not spend anything: the resolver calls it on every change.
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

    /// Once is the whole point: after the takeover the web app's key is never consulted again.
    func testWebCountIsAdoptedOnlyOnce() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 1
        _ = makeCounter()

        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 3
        let second = makeCounter()

        XCTAssertEqual(second.displayCount, 1)
    }

    /// The takeover runs whether or not there was anything to take, so a value written afterwards
    /// belongs to a web app that is no longer the authority.
    func testWebCountAppearingAfterTheTakeoverIsIgnored() {
        _ = makeCounter()

        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 3
        let second = makeCounter()

        XCTAssertEqual(second.displayCount, 0)
        XCTAssertTrue(second.consumeDisplay())
    }

    /// Deliberate: the takeover is about state, not about showing anything, so deferring it until
    /// the flag is on would risk missing it entirely.
    func testTheTakeoverHappensEvenWithTheFlagOff() {
        webStorage.entries[AttachmentPrivacyDisplayCounter.webEntryKey] = 2

        _ = makeCounter(isEnabled: false)

        XCTAssertEqual(makeCounter().displayCount, 2)
    }

    func testAbsentWebCountLeavesTheCountAtZero() {
        let counter = makeCounter()

        XCTAssertEqual(counter.displayCount, 0)
    }

    /// Erring towards showing a required disclosure.
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

    /// Otherwise the burn would clear our count, re-adopt the web app's, and the message would
    /// never come back.
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

    /// The Fire Button clears the persistent count; a Fire Window's dies with the window.
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

/// Stores entries so the migration can be driven; everything else is unused here.
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
