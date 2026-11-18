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

    // MARK: - The kill switch

    func testNothingIsAllowedWithTheFlagOff() {
        let disclosure = makeDisclosure(isEnabled: false)

        XCTAssertFalse(disclosure.canShow)
        XCTAssertFalse(disclosure.claim())
        XCTAssertFalse(store.hasShown)
    }

    // MARK: - Taking over the web app's flag

    /// The web app wrote a flag, an older count, or (what it mirrors from localStorage) a string.
    func testWhenTheWebValueSaysShownThenItIsAdoptedOtherwiseItStaysUnshown() throws {
        let rows: [(name: String, webValue: Any?, adopted: Bool)] = [
            ("bool true", true, true),
            ("bool false", false, false),
            ("count", 2, true),
            ("count of zero", 0, false),
            ("string flag", "true", true),
            ("false string flag", "false", false),
            ("string count", "2", true),
            ("unparseable type", ["unexpected": true], false),
            ("absent", nil, false)
        ]

        for row in rows {
            store = AttachmentPrivacyDisclosureStore(keyValueStore: try MockKeyValueFileStore())
            webStorage = FakeWebKeyStorage()
            webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = row.webValue

            XCTAssertEqual(makeDisclosure().canShow, !row.adopted, "row: \(row.name)")
            XCTAssertEqual(store.hasShown, row.adopted, "row: \(row.name)")
        }
    }

    /// The web app may show it at any point before the front end delegates to us, so a flag that
    /// appears after we have already answered still counts.
    func testAWebFlagAppearingLaterIsHonoured() {
        XCTAssertTrue(makeDisclosure().canShow)

        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true

        XCTAssertFalse(makeDisclosure().canShow)
    }

    /// Adopted on the first read, so the web app replacing its own entries can't bring the message
    /// back.
    func testAnAdoptedFlagSurvivesTheWebKeyGoingAway() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true
        XCTAssertFalse(makeDisclosure().canShow)

        webStorage.entries.removeAll()

        XCTAssertFalse(makeDisclosure().canShow)
        XCTAssertTrue(store.hasShown)
    }

    /// A failed read is not an answer: the next decision reads again.
    func testAFailedReadIsNotAnAnswer() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true
        webStorage.readError = TestError.unreadable

        XCTAssertTrue(makeDisclosure().canShow)

        webStorage.readError = nil
        XCTAssertFalse(makeDisclosure().canShow)
    }

    func testAnAbsentStorageHandlerIsNotAnAnswer() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true

        XCTAssertTrue(makeDisclosure(webKeySource: nil).canShow)

        XCTAssertFalse(makeDisclosure().canShow)
    }

    /// With the flag off nothing is read or recorded, so the web app keeps owning it.
    func testNothingIsRecordedWithTheFlagOff() {
        webStorage.entries[AttachmentPrivacyDisclosure.webEntryKey] = true
        let disabled = makeDisclosure(isEnabled: false)

        _ = disabled.canShow
        disabled.claim()

        XCTAssertFalse(store.hasShown)
    }

    /// The native omnibar holds one of these for the window's lifetime, so the instance built with
    /// the flag off has to adopt the web flag itself once it flips.
    func testTheWebFlagIsAdoptedByAnInstanceThatOutlivesTheFlagFlip() {
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

    /// The web key goes with it, or the next read would adopt it straight back.
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
        XCTAssertFalse(gate.shouldShow(attachmentKind: nil, tabID: "A"))
        XCTAssertFalse(store.hasShown)
    }

    func testStagingAnAttachmentClaimsTheDisplay() {
        XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: "A"))
        XCTAssertTrue(store.hasShown)
    }

    func testResolvingRepeatedlyWhileStagedKeepsShowing() {
        for _ in 0..<5 {
            XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: "A"))
        }
    }

    /// Emptying the attachments ends the display, and the one display is already spent.
    func testRemovingAndReattachingDoesNotShowAgain() {
        XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: "A"))
        XCTAssertFalse(gate.shouldShow(attachmentKind: nil, tabID: "A"))

        XCTAssertFalse(gate.shouldShow(attachmentKind: .file, tabID: "A"))
    }

    func testOnlyOneTabGetsTheDisplay() {
        XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: "A"))
        XCTAssertFalse(gate.shouldShow(attachmentKind: .file, tabID: "B"))
    }

    func testReturningToTheShowingTabKeepsIt() {
        _ = gate.shouldShow(attachmentKind: .file, tabID: "A")
        _ = gate.shouldShow(attachmentKind: .file, tabID: "B")

        XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: "A"))
    }

    func testAnotherTabsEmptyingLeavesTheShowingTabAlone() {
        _ = gate.shouldShow(attachmentKind: .file, tabID: "A")

        XCTAssertFalse(gate.shouldShow(attachmentKind: nil, tabID: "B"))

        XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: "A"))
    }

    func testASurfaceWithoutATabShowsOnce() {
        XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: nil))
        XCTAssertTrue(gate.shouldShow(attachmentKind: .file, tabID: nil))
    }

    func testTheKindOfTheStartedDisplayIsReported() {
        var started: [AttachmentPrivacyDisclosureKind] = []
        gate.onDisplayStarted = { started.append($0) }

        XCTAssertTrue(gate.shouldShow(attachmentKind: .image, tabID: "A"))
        XCTAssertTrue(gate.shouldShow(attachmentKind: .image, tabID: "A"))

        XCTAssertEqual(started, [.image])
    }

    func testADeniedDisplayIsNotReported() {
        _ = gate.shouldShow(attachmentKind: .file, tabID: "A")
        var started: [AttachmentPrivacyDisclosureKind] = []
        gate.onDisplayStarted = { started.append($0) }

        XCTAssertFalse(gate.shouldShow(attachmentKind: .file, tabID: "B"))

        XCTAssertTrue(started.isEmpty)
    }

    func testADeniedTabNeverShows() {
        _ = gate.shouldShow(attachmentKind: .file, tabID: "A")

        XCTAssertFalse(gate.shouldShow(attachmentKind: .file, tabID: "B"))
        XCTAssertFalse(gate.shouldShow(attachmentKind: .file, tabID: "B"))
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
