//
//  UTIPromptLengthGateTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIPromptLengthGateTests: XCTestCase {

    private var promptText = ""
    private var attachments: [UnifiedToggleInputAttachment] = []
    private var attachmentLimits: AIChatAttachmentTierLimits?
    private var isEnabled = true
    private var events: [String] = []
    private var pastedTextToEdit: UUID?

    private func makeGate() -> UTIPromptLengthGate {
        UTIPromptLengthGate(
            inputs: .init(
                promptText: { [unowned self] in promptText },
                attachments: { [unowned self] in attachments },
                attachmentLimits: { [unowned self] in attachmentLimits },
                isEnabled: { [unowned self] in isEnabled }
            ),
            outputs: .init(
                onOverLimitChanged: { [unowned self] length, pastedTextToEdit in
                    events.append("footer:\(length.map { "\($0.count)/\($0.limit)" } ?? "nil")")
                    self.pastedTextToEdit = pastedTextToEdit
                },
                onPromptOverLimitChanged: { [unowned self] in events.append("over:\($0)") }
            )
        )
    }

    private func text(_ count: Int) -> String { String(repeating: "a", count: count) }

    func testOverLimitReportsTheFooterBeforeTheInput() {
        let gate = makeGate()
        promptText = text(16_001)

        gate.refresh()

        XCTAssertEqual(events, ["footer:16001/16000", "over:true"])
        XCTAssertTrue(gate.isSubmitBlocked)
    }

    func testTypingWhileOverReportsTheNewCount() {
        let gate = makeGate()
        promptText = text(16_001)
        gate.refresh()
        events.removeAll()

        promptText = text(16_002)
        gate.refresh()

        XCTAssertEqual(events, ["footer:16002/16000", "over:true"])
    }

    func testClearingTheDraftReleasesEverything() {
        let gate = makeGate()
        promptText = text(16_001)
        gate.refresh()
        events.removeAll()

        promptText = ""
        gate.refresh()

        XCTAssertEqual(events, ["footer:nil", "over:false"])
        XCTAssertFalse(gate.isSubmitBlocked)
    }

    func testPastesCountTowardsTheLimitAndImagesLowerIt() {
        let gate = makeGate()
        attachmentLimits = makeLimits(maxInputCharsWithAttachments: 4_500)
        attachments = [.pastedText(AIChatPastedText(content: text(4_000))), .image(AIChatImageAttachment(image: UIImage(), fileName: "a.jpg"))]
        promptText = text(501)

        gate.refresh()

        XCTAssertEqual(events.first, "footer:4501/4500")
    }

    func testOverLimitOffersTheLargestPasteForEditingAndTheFirstOnATie() {
        let gate = makeGate()
        let small = AIChatPastedText(content: text(4_000))
        let largest = AIChatPastedText(content: text(6_000))
        let tiedLater = AIChatPastedText(content: text(6_000))
        attachments = [.pastedText(small), .pastedText(largest), .pastedText(tiedLater)]
        promptText = text(1)

        gate.refresh()

        XCTAssertEqual(events.first, "footer:16001/16000")
        XCTAssertEqual(pastedTextToEdit, largest.id)
    }

    func testOverLimitWithoutAPasteOffersNothingToEditAndUnderTheLimitNeither() {
        let gate = makeGate()
        promptText = text(16_001)
        gate.refresh()
        XCTAssertNil(pastedTextToEdit)

        promptText = ""
        attachments = [.pastedText(AIChatPastedText(content: text(5_000)))]
        gate.refresh()
        XCTAssertEqual(events.last, "over:false")
        XCTAssertNil(pastedTextToEdit)
    }

    func testFilesDoNotLowerTheLimit() {
        let gate = makeGate()
        attachmentLimits = makeLimits(maxInputCharsWithAttachments: 4_500)
        attachments = [.file(AIChatFileAttachment(data: Data(), fileName: "a.pdf", mimeType: "application/pdf"))]
        promptText = text(4_501)

        gate.refresh()

        XCTAssertEqual(events, ["footer:nil", "over:false"])
        XCTAssertEqual(gate.promptLength?.limit, 16_000)
    }

    func testDisabledGateReportsNothingAndReleasesAnEarlierBlock() {
        let gate = makeGate()
        promptText = text(16_001)
        gate.refresh()
        events.removeAll()

        isEnabled = false
        gate.refresh()

        XCTAssertEqual(events, ["footer:nil", "over:false"])
        XCTAssertNil(gate.promptLength)
    }

    func testSheetLimitIsWhatThePasteMayGrowToAndNeverNegative() {
        let gate = makeGate()
        let paste = AIChatPastedText(content: text(5_000))
        attachments = [.pastedText(paste)]
        promptText = text(1_000)
        gate.refresh()
        XCTAssertEqual(gate.sheetLimit(for: paste), 15_000)

        promptText = text(17_000)
        gate.refresh()
        XCTAssertEqual(gate.sheetLimit(for: paste), 0, "Clamped for display; Save stays off above it")
    }

    private func makeLimits(maxInputCharsWithAttachments: Int) -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: maxInputCharsWithAttachments)
        )
    }
}
