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

    private func makeGate() -> UTIPromptLengthGate {
        UTIPromptLengthGate(
            inputs: .init(
                promptText: { [unowned self] in promptText },
                attachments: { [unowned self] in attachments },
                attachmentLimits: { [unowned self] in attachmentLimits },
                isEnabled: { [unowned self] in isEnabled }
            ),
            onOverLimitChanged: { [unowned self] in events.append($0.map { "\($0.count)/\($0.limit)" } ?? "nil") }
        )
    }

    private func text(_ count: Int) -> String { String(repeating: "a", count: count) }

    func testOverLimitReportsTheLength() {
        let gate = makeGate()
        promptText = text(16_001)

        gate.refresh()

        XCTAssertEqual(events, ["16001/16000"])
    }

    func testSubmissionMeasuresTheSentTextNotTheLastRefreshedDraft() {
        let gate = makeGate()
        attachments = [.pastedText(AIChatPastedText(content: text(6_000)))]
        promptText = text(10)
        gate.refresh()

        XCTAssertTrue(gate.blocksSubmission(of: text(10_001)))
        XCTAssertFalse(gate.blocksSubmission(of: text(10_000)))

        promptText = text(16_001)
        gate.refresh()
        XCTAssertFalse(gate.blocksSubmission(of: text(10)))

        isEnabled = false
        XCTAssertFalse(gate.blocksSubmission(of: text(16_001)))
    }

    func testTypingWhileOverReportsTheNewCount() {
        let gate = makeGate()
        promptText = text(16_001)
        gate.refresh()
        events.removeAll()

        promptText = text(16_002)
        gate.refresh()

        XCTAssertEqual(events, ["16002/16000"])
    }

    func testClearingTheDraftReleasesEverything() {
        let gate = makeGate()
        promptText = text(16_001)
        gate.refresh()
        events.removeAll()

        promptText = ""
        gate.refresh()

        XCTAssertEqual(events, ["nil"])
    }

    func testPastesCountTowardsTheLimitAndImagesLowerIt() {
        let gate = makeGate()
        attachmentLimits = makeLimits(maxInputCharsWithAttachments: 4_500)
        attachments = [.pastedText(AIChatPastedText(content: text(4_000))), .image(AIChatImageAttachment(image: UIImage(), fileName: "a.jpg"))]
        promptText = text(501)

        gate.refresh()

        XCTAssertEqual(events, ["4501/4500"])
    }

    func testFilesDoNotLowerTheLimit() {
        let gate = makeGate()
        attachmentLimits = makeLimits(maxInputCharsWithAttachments: 4_500)
        attachments = [.file(AIChatFileAttachment(data: Data(), fileName: "a.pdf", mimeType: "application/pdf"))]
        promptText = text(4_501)

        gate.refresh()

        XCTAssertEqual(events, ["nil"])
    }

    func testDisabledGateReportsNothingAndReleasesAnEarlierBlock() {
        let gate = makeGate()
        promptText = text(16_001)
        gate.refresh()
        events.removeAll()

        isEnabled = false
        gate.refresh()

        XCTAssertEqual(events, ["nil"])
    }

    func testEachPastesSheetCountsTheWholePromptAgainstTheFullLimit() {
        let gate = makeGate()
        let long = AIChatPastedText(content: text(15_753))
        let short = AIChatPastedText(content: text(4_121))
        attachments = [.pastedText(long), .pastedText(short)]

        for paste in [long, short] {
            let rules = PastedTextSheetRules(original: paste, mode: gate.sheetMode(for: paste))
            XCTAssertEqual(rules.subtitle(for: paste.content), PastedTextSheetSubtitle(count: 19_874, limit: 16_000))
        }
        let rules = PastedTextSheetRules(original: short, mode: gate.sheetMode(for: short))
        XCTAssertEqual(rules.subtitle(for: text(247))?.isOverLimit, false, "Trimming either paste brings the total under")
    }

    func testSheetCountsTheWholePromptAgainstTheLowerLimitWhileAnImageIsAttached() {
        let gate = makeGate()
        attachmentLimits = makeLimits(maxInputCharsWithAttachments: 4_500)
        let paste = AIChatPastedText(content: text(4_000))
        attachments = [.pastedText(paste), .image(AIChatImageAttachment(image: UIImage(), fileName: "a.jpg"))]
        promptText = text(100)

        let rules = PastedTextSheetRules(original: paste, mode: gate.sheetMode(for: paste))

        XCTAssertEqual(rules.subtitle(for: paste.content), PastedTextSheetSubtitle(count: 4_100, limit: 4_500))
        XCTAssertEqual(rules.subtitle(for: text(4_401))?.isOverLimit, true)
    }

    private func makeLimits(maxInputCharsWithAttachments: Int) -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: maxInputCharsWithAttachments)
        )
    }
}
