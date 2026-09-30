//
//  AttachmentPrivacyDisclosureTests.swift
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
@_spi(Testing) import Persistence
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AttachmentPrivacyDisclosureTests: XCTestCase {

    private var store: AttachmentPrivacyDisclosureStore!
    private var webStorage: FakeWebKeyStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = AttachmentPrivacyDisclosureStore(keyValueStore: try MockKeyValueFileStore())
        webStorage = FakeWebKeyStorage()
    }

    override func tearDown() {
        store = nil
        webStorage = nil
        super.tearDown()
    }

    // MARK: - The single display

    func testTheFirstClaimIsGrantedAndTheSecondIsNot() {
        let disclosure = makeDisclosure()

        XCTAssertTrue(disclosure.claim())
        XCTAssertFalse(disclosure.claim())
        XCTAssertTrue(store.hasShown)
    }

    func testCanShowFollowsTheState() {
        let disclosure = makeDisclosure()

        XCTAssertTrue(disclosure.canShow)
        disclosure.claim()
        XCTAssertFalse(disclosure.canShow)
    }

    func testCanShowDoesNotClaim() {
        let disclosure = makeDisclosure()

        _ = disclosure.canShow
        _ = disclosure.canShow

        XCTAssertFalse(store.hasShown)
    }

    /// Probabilistic by nature — it fails loudly if the claim stops being atomic, which is what
    /// the shared store can't do on its own.
    func testOnlyOneOfManyConcurrentCallersClaims() {
        let grantLock = NSLock()
        var grants: [Bool] = []

        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            let granted = self.makeDisclosure().claim()
            grantLock.withLock { grants.append(granted) }
        }

        XCTAssertEqual(grants.filter { $0 }.count, 1)
        XCTAssertTrue(store.hasShown)
    }

    // MARK: - The kill switch

    func testNothingIsAllowedWithTheFlagOff() {
        let disclosure = makeDisclosure(isEnabled: false)

        XCTAssertFalse(disclosure.canShow)
        XCTAssertFalse(disclosure.claim())
        XCTAssertFalse(store.hasShown)
    }

    // MARK: - Taking over the web app's flag

    func testWebFlagIsAdopted() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true

        XCTAssertFalse(makeDisclosure().canShow)
        XCTAssertTrue(store.hasShown)
    }

    func testAnUnsetWebFlagLeavesItUnshown() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = false

        XCTAssertTrue(makeDisclosure().canShow)
        XCTAssertFalse(store.hasShown)
    }

    /// The count the web app wrote before it settled on a flag.
    func testAWebCountIsAdopted() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = 2

        XCTAssertFalse(makeDisclosure().canShow)
    }

    func testAWebCountOfZeroLeavesItUnshown() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = 0

        XCTAssertTrue(makeDisclosure().canShow)
    }

    func testAWebCountIsAdoptedFromAString() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = "2"

        XCTAssertFalse(makeDisclosure().canShow)
    }

    func testAnUnparseableWebValueLeavesItUnshown() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = ["unexpected": true]

        XCTAssertTrue(makeDisclosure().canShow)
    }

    func testAnAbsentWebFlagLeavesItUnshown() {
        XCTAssertTrue(makeDisclosure().canShow)
        XCTAssertFalse(store.hasShown)
    }

    func testAWebFlagAppearingAfterTheTakeoverIsIgnored() {
        _ = makeDisclosure().canShow

        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true

        XCTAssertTrue(makeDisclosure().canShow)
    }

    /// Otherwise a read taken before Duck.ai's storage is readable spends the takeover on nothing,
    /// and the message shows again after the web app already showed it.
    func testAFailedReadLeavesTheTakeoverForTheNextRead() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true
        webStorage.readError = TestError.unreadable

        XCTAssertTrue(makeDisclosure().canShow)

        webStorage.readError = nil
        XCTAssertFalse(makeDisclosure().canShow)
    }

    func testAnAbsentStorageHandlerLeavesTheTakeoverForTheNextRead() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true

        XCTAssertTrue(makeDisclosure(webKeySource: nil).canShow)

        XCTAssertFalse(makeDisclosure().canShow)
    }

    /// Until the flag is on the web app still owns the disclosure and can write the key at any
    /// time, so taking the handover early would leave a later `true` unread.
    func testTheTakeoverWaitsForTheFlag() {
        let disabled = makeDisclosure(isEnabled: false)
        _ = disabled.canShow
        disabled.claim()

        XCTAssertFalse(store.hasTakenOverWebFlag)

        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true

        XCTAssertFalse(makeDisclosure().canShow)
    }

    /// The native omnibar holds one of these for the window's lifetime, so the instance built with
    /// the flag off has to take the handover itself once it flips.
    func testTheTakeoverHappensOnAnInstanceThatOutlivesTheFlagFlip() {
        let flagger = MockFeatureFlagger(
            featuresStub: [FeatureFlag.aiChatAttachmentPrivacyDisclosure.rawValue: false]
        )
        let disclosure = AttachmentPrivacyDisclosure(store: store, webKeySource: webStorage, featureFlagger: flagger)
        _ = disclosure.canShow

        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true
        flagger.featuresStub = [FeatureFlag.aiChatAttachmentPrivacyDisclosure.rawValue: true]

        XCTAssertFalse(disclosure.canShow)
        XCTAssertFalse(disclosure.claim())
    }

    // MARK: - Reset

    func testResetClearsTheState() {
        let disclosure = makeDisclosure()
        disclosure.claim()

        disclosure.reset()

        XCTAssertFalse(store.hasShown)
        XCTAssertTrue(disclosure.canShow)
    }

    func testResetDeletesTheWebKey() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true
        let disclosure = makeDisclosure()

        disclosure.reset()

        XCTAssertNil(webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey])
    }

    /// Otherwise the debug reset re-adopts the web flag and the message never comes back.
    func testResetDoesNotLeaveTheWebFlagToBeAdoptedAgain() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true
        let disclosure = makeDisclosure()
        disclosure.reset()

        XCTAssertTrue(makeDisclosure().canShow)
    }

    // MARK: -

    private func makeDisclosure(isEnabled: Bool = true) -> AttachmentPrivacyDisclosure {
        makeDisclosure(webKeySource: webStorage, isEnabled: isEnabled)
    }

    private func makeDisclosure(webKeySource: DuckAiNativeStorageHandling?,
                                isEnabled: Bool = true) -> AttachmentPrivacyDisclosure {
        AttachmentPrivacyDisclosure(
            store: store,
            webKeySource: webKeySource,
            featureFlagger: MockFeatureFlagger(
                featuresStub: [FeatureFlag.aiChatAttachmentPrivacyDisclosure.rawValue: isEnabled]
            )
        )
    }
}

final class AttachmentPrivacyDisclosureGateTests: XCTestCase {

    private var store: AttachmentPrivacyDisclosureStore!
    private var gate: AttachmentPrivacyDisclosureGate!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = AttachmentPrivacyDisclosureStore(keyValueStore: try MockKeyValueFileStore())
        gate = AttachmentPrivacyDisclosureGate(
            disclosure: AttachmentPrivacyDisclosure(
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
        XCTAssertFalse(store.hasShown)
    }

    func testStagingAnAttachmentClaimsTheDisplay() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertTrue(store.hasShown)
    }

    func testResolvingRepeatedlyWhileStagedKeepsShowing() {
        for _ in 0..<5 {
            XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        }
    }

    /// Emptying the attachments ends the display, and the one display is already spent.
    func testRemovingAndReattachingDoesNotShowAgain() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: false, tabID: "A"))

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
    }

    func testAttachingAgainAfterSubmittingDoesNotShowAgain() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        gate.displayEnded(tabID: "A")

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
    }

    func testOnlyOneTabGetsTheDisplay() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))
    }

    func testReturningToTheShowingTabKeepsIt() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "B")

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
    }

    func testAnotherTabsSubmitLeavesTheShowingTabAlone() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")

        gate.displayEnded(tabID: "B")

        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: "A"))
    }

    func testASurfaceWithoutATabShowsOnce() {
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: nil))
        XCTAssertTrue(gate.shouldShow(hasStagedAttachment: true, tabID: nil))
    }

    func testADeniedTabNeverShows() {
        _ = gate.shouldShow(hasStagedAttachment: true, tabID: "A")

        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))
        XCTAssertFalse(gate.shouldShow(hasStagedAttachment: true, tabID: "B"))
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
