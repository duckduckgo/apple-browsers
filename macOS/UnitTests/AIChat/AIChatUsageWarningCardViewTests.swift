//
//  AIChatUsageWarningCardViewTests.swift
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

/// Required messages stack, as on iOS: the attachment notice shows under the Terms of Service
/// disclaimer instead of waiting for it to be accepted.
@MainActor
final class AIChatUsageWarningCardViewTests: XCTestCase {

    private let rowHeight = AIChatUsageWarningCardView.Constants.contentHeight

    func testWhenTheDisclaimerShowsAloneThenTheCardIsOneRow() {
        let card = AIChatUsageWarningCardView()

        card.updateForTermsOfService(sendButton: .ask, stackingAttachmentPrivacy: false)

        XCTAssertTrue(card.isShowingTermsOfService)
        XCTAssertEqual(card.bandHeight, rowHeight)
        XCTAssertTrue(stackedDisclosureTextView(in: card).isHidden)
    }

    func testWhenTheAttachmentNoticeStacksUnderTheDisclaimerThenTheCardIsTwoRows() {
        let card = AIChatUsageWarningCardView()

        card.updateForTermsOfService(sendButton: .ask, stackingAttachmentPrivacy: true)

        XCTAssertTrue(card.isShowingTermsOfService)
        XCTAssertEqual(card.bandHeight, rowHeight * 2)
        XCTAssertFalse(stackedDisclosureTextView(in: card).isHidden)
        XCTAssertTrue(stackedDisclosureTextView(in: card).string.contains(UserText.aiChatAttachmentPrivacyLearnMore))
    }

    /// Once the terms are accepted, the attachment notice moves up to the card's only row.
    func testWhenTheAttachmentNoticeShowsAloneThenTheStackedRowIsDropped() {
        let card = AIChatUsageWarningCardView()
        card.updateForTermsOfService(sendButton: .ask, stackingAttachmentPrivacy: true)

        card.updateForAttachmentPrivacy()

        XCTAssertFalse(card.isShowingTermsOfService)
        XCTAssertEqual(card.bandHeight, rowHeight)
        XCTAssertTrue(stackedDisclosureTextView(in: card).isHidden)
    }

    func testWhenAnotherMessageReplacesTheStackThenTheStackedRowIsDropped() {
        let card = AIChatUsageWarningCardView()
        card.updateForTermsOfService(sendButton: .ask, stackingAttachmentPrivacy: true)

        card.update(with: DuckAiHighUsageModelNotice(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8"))

        XCTAssertFalse(card.isShowingTermsOfService)
        XCTAssertEqual(card.bandHeight, rowHeight)
        XCTAssertTrue(stackedDisclosureTextView(in: card).isHidden)
    }

    func testWhenStackedThenEachRowsLinkOpensItsOwnPage() {
        let card = AIChatUsageWarningCardView()
        var openedTermsOfService = 0
        var openedAttachmentPrivacy = 0
        card.onTermsOfServiceLink = { openedTermsOfService += 1 }
        card.onLearnMore = { openedAttachmentPrivacy += 1 }
        card.updateForTermsOfService(sendButton: .ask, stackingAttachmentPrivacy: true)

        _ = card.textView(disclosureTextView(in: card), clickedOnLink: URL.aiChatPrivacyTerms, at: 0)
        _ = card.textView(stackedDisclosureTextView(in: card), clickedOnLink: URL.aiChatPrivacy, at: 0)

        XCTAssertEqual(openedTermsOfService, 1)
        XCTAssertEqual(openedAttachmentPrivacy, 1)
    }

    private func disclosureTextView(in card: AIChatUsageWarningCardView) -> NSTextView {
        textView(identifiedBy: "AIChatUsageWarningCardView.disclosureTextView", in: card)
    }

    private func stackedDisclosureTextView(in card: AIChatUsageWarningCardView) -> NSTextView {
        textView(identifiedBy: "AIChatUsageWarningCardView.stackedDisclosureTextView", in: card)
    }

    private func textView(identifiedBy identifier: String, in card: AIChatUsageWarningCardView) -> NSTextView {
        guard let textView = card.subviews.first(where: { $0.accessibilityIdentifier() == identifier }) as? NSTextView else {
            XCTFail("No text view identified by \(identifier)")
            return NSTextView()
        }
        return textView
    }
}
