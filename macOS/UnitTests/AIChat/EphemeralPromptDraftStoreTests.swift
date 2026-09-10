//
//  EphemeralPromptDraftStoreTests.swift
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
import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class EphemeralPromptDraftStoreTests: XCTestCase {

    private var store: EphemeralPromptDraftStore!

    override func setUp() {
        super.setUp()
        store = EphemeralPromptDraftStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    private func makeFileAttachment(name: String) -> AIChatFileAttachment {
        AIChatFileAttachment(data: Data("pdf".utf8), fileName: name, mimeType: "application/pdf")
    }

    private func makeImageAttachment(name: String) -> AIChatImageAttachment {
        AIChatImageAttachment(image: NSImage(size: NSSize(width: 1, height: 1)), fileName: name, skipResize: true)
    }

    // MARK: - Text

    func testWhenTextIsUpdatedThenItIsReadBack() {
        store.updateText("what is a duck", markInteraction: true)

        XCTAssertEqual(store.text, "what is a duck")
        XCTAssertTrue(store.hasUserInteractedWithText)
    }

    func testWhenTextIsUpdatedWithoutMarkingInteractionThenInteractionStaysUnset() {
        store.updateText("what is a duck", markInteraction: false)

        XCTAssertEqual(store.text, "what is a duck")
        XCTAssertFalse(store.hasUserInteractedWithText)
    }

    func testWhenTextIsClearedThenInteractionIsNotMarked() {
        store.updateText("", markInteraction: true)

        XCTAssertFalse(store.hasUserInteractedWithText)
    }

    // MARK: - Selection

    func testWhenSelectionIsSetThenItIsReadBack() {
        store.updateText("abcdef", markInteraction: true)
        store.updateSelection(NSRange(location: 2, length: 3))

        XCTAssertEqual(store.selectionRange, NSRange(location: 2, length: 3))
    }

    func testWhenSelectionExtendsPastTheTextThenItIsClamped() {
        store.updateText("abc", markInteraction: true)
        store.updateSelection(NSRange(location: 1, length: 99))

        XCTAssertEqual(store.selectionRange, NSRange(location: 1, length: 2))
    }

    func testWhenTextShrinksBelowTheSelectionThenTheSelectionIsClamped() {
        store.updateText("abcdef", markInteraction: true)
        store.updateSelection(NSRange(location: 5, length: 1))

        store.updateText("ab", markInteraction: true)

        XCTAssertEqual(store.selectionRange, NSRange(location: 2, length: 0))
    }

    // MARK: - Tool mode and attachments

    func testWhenToolModeIsSetThenItIsReadBack() {
        store.setAIChatToolMode(.webSearch)

        XCTAssertEqual(store.aiChatToolMode, .webSearch)
    }

    func testWhenAttachmentsAreSetThenThePanelListCarriesEveryKindInInsertionOrder() {
        let image = makeImageAttachment(name: "shot.png")
        let file = makeFileAttachment(name: "report.pdf")

        store.setAIChatAttachments([image])
        store.setAIChatFileAttachments([file])

        XCTAssertEqual(store.aiChatAttachments.count, 1)
        XCTAssertEqual(store.aiChatFileAttachments.count, 1)
        XCTAssertEqual(store.aiChatPanelAttachments.map(\.attachmentId),
                       ["image:\(image.id.uuidString)", "file:\(file.id.uuidString)"])
    }

    func testWhenAnAttachmentIsRemovedThenItLeavesThePanelList() {
        let image = makeImageAttachment(name: "shot.png")
        let file = makeFileAttachment(name: "report.pdf")
        store.setAIChatAttachments([image])
        store.setAIChatFileAttachments([file])

        store.setAIChatAttachments([])

        XCTAssertEqual(store.aiChatPanelAttachments.map(\.attachmentId), ["file:\(file.id.uuidString)"])
    }

    // MARK: - Reset

    func testWhenTheStoreIsResetThenEveryFieldIsCleared() {
        store.updateText("what is a duck", markInteraction: true)
        store.updateSelection(NSRange(location: 3, length: 2))
        store.setAIChatToolMode(.imageGeneration)
        store.setAIChatAttachments([makeImageAttachment(name: "shot.png")])
        store.setAIChatFileAttachments([makeFileAttachment(name: "report.pdf")])

        store.reset()

        XCTAssertEqual(store.text, "")
        XCTAssertFalse(store.hasUserInteractedWithText)
        XCTAssertEqual(store.selectionRange, NSRange(location: 0, length: 0))
        XCTAssertNil(store.aiChatToolMode)
        XCTAssertTrue(store.aiChatAttachments.isEmpty)
        XCTAssertTrue(store.aiChatFileAttachments.isEmpty)
        XCTAssertTrue(store.aiChatTabAttachments.isEmpty)
        XCTAssertTrue(store.aiChatPanelAttachments.isEmpty)
    }
}
