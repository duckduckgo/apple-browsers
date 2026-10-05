//
//  MultiTabMentionControllerTests.swift
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

import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class MultiTabMentionControllerTests: XCTestCase {
    func testWhenSelectionSucceedsThenRemovesOnlyTokenAndPlacesCaretAtItsStart() async {
        let fixture = MentionFixture()
        fixture.setText("Compare @wiki with this")
        await presentSuggestions(fixture)

        fixture.controller.accept(fixture.candidate)

        XCTAssertEqual(fixture.attachmentAttempts, [fixture.candidate.tabId])
        XCTAssertEqual(fixture.selectedIDs, [fixture.candidate.tabId])
        XCTAssertEqual(fixture.textView.text, "Compare  with this")
        XCTAssertEqual(fixture.textView.selectedRange, NSRange(location: 8, length: 0))
        XCTAssertNil(fixture.suggestions)
    }

    func testWhenAttachmentIsRejectedThenPreservesTextAndSelection() async {
        for alreadyAttached in [false, true] {
            let fixture = MentionFixture()
            fixture.acceptsAttachment = false
            fixture.setText("Compare @wiki with this")
            let originalSelection = fixture.textView.selectedRange
            await presentSuggestions(fixture)
            if alreadyAttached {
                fixture.selectedIDs = [fixture.candidate.tabId]
            }

            fixture.controller.accept(fixture.candidate)

            XCTAssertEqual(fixture.attachmentAttempts, alreadyAttached ? [] : [fixture.candidate.tabId])
            XCTAssertEqual(fixture.selectedIDs, alreadyAttached ? [fixture.candidate.tabId] : [])
            XCTAssertEqual(fixture.textView.text, "Compare @wiki with this")
            XCTAssertEqual(fixture.textView.selectedRange, originalSelection)
            XCTAssertNil(fixture.suggestions)
        }
    }

    func testWhenCaretLeavesAndReturnsToMentionThenSuggestionsCloseAndReopen() async {
        let fixture = MentionFixture()
        fixture.setText("@wiki")
        await presentSuggestions(fixture)
        let dismissed = expectation(description: "Suggestions dismissed outside mention")
        fixture.onUpdate = { if $0 == nil { dismissed.fulfill() } }

        fixture.textView.selectedRange = NSRange(location: 0, length: 0)
        fixture.controller.selectionDidChange(in: fixture.textView)
        await fulfillment(of: [dismissed], timeout: 1)
        XCTAssertNil(fixture.suggestions)

        let reopened = expectation(description: "Suggestions reopened by caret movement")
        fixture.onUpdate = { if $0 != nil { reopened.fulfill() } }
        fixture.textView.selectedRange = NSRange(location: 5, length: 0)
        fixture.controller.selectionDidChange(in: fixture.textView)
        await fulfillment(of: [reopened], timeout: 1)
        XCTAssertEqual(fixture.suggestions?.map(\.candidate.tabId), [fixture.candidate.tabId])
    }

    func testWhenDismissedBeforePendingUpdateThenSuggestionsDoNotReopen() async {
        let fixture = MentionFixture()
        fixture.setText("@wiki")
        let reopened = expectation(description: "Cancelled update must not present suggestions")
        reopened.isInverted = true
        fixture.onUpdate = { if $0 != nil { reopened.fulfill() } }

        fixture.controller.textDidChange(in: fixture.textView)
        fixture.controller.dismiss()
        fixture.controller.refresh()

        await fulfillment(of: [reopened], timeout: 0.1)
        XCTAssertNil(fixture.suggestions)
        XCTAssertEqual(fixture.candidateReadCount, 0)
        XCTAssertEqual(fixture.textView.text, "@wiki")
    }

    func testWhenAtCapacityThenAttachedTabsAreExcludedAndOtherTabsAreDisabled() async throws {
        let fixture = MentionFixture()
        let other = MultiTabAttachmentCandidate(tabId: "other", title: "Wikipedia other", url: fixture.candidate.url)
        let currentPage = MultiTabAttachmentCandidate(tabId: "current", title: "Wikipedia current",
                                                      url: fixture.candidate.url, isCurrentTab: true)
        fixture.candidates.insert(currentPage, at: 0)
        fixture.candidates.append(other)
        fixture.selectedIDs = [currentPage.tabId, fixture.candidate.tabId]
        fixture.allowsAttachment = false
        fixture.setText("@wiki")
        await presentSuggestions(fixture)

        let suggestions = try XCTUnwrap(fixture.suggestions)
        XCTAssertEqual(suggestions.map(\.candidate.tabId), [other.tabId])
        XCTAssertEqual(suggestions.map(\.isEnabled), [false])

        fixture.controller.accept(other)
        XCTAssertTrue(fixture.attachmentAttempts.isEmpty)
        XCTAssertEqual(fixture.selectedIDs, [currentPage.tabId, fixture.candidate.tabId])
        XCTAssertEqual(fixture.textView.text, "@wiki")
    }

    func testWhenQueryHasNoMatchesThenHidesSuggestionsUntilQueryMatchesAgain() async {
        let fixture = MentionFixture()
        let cases: [(text: String, expectedIDs: [TabUID]?)] = [
            ("@wiki", [fixture.candidate.tabId]),
            ("@xyz", nil),
            ("@xyz ", nil),
            ("@xyz more", nil),
            ("@ can you summarise this", nil),
            ("@xyz\t", nil),
            ("@wiki", [fixture.candidate.tabId]),
        ]

        for testCase in cases {
            fixture.textView.text = testCase.text
            fixture.textView.selectedRange = NSRange(location: (testCase.text as NSString).length, length: 0)
            let originalSelection = fixture.textView.selectedRange
            let updated = expectation(description: "Suggestions updated for \(testCase.text)")
            fixture.onUpdate = { _ in updated.fulfill() }

            fixture.controller.textDidChange(in: fixture.textView)
            await fulfillment(of: [updated], timeout: 1)
            fixture.onUpdate = nil

            XCTAssertEqual(fixture.suggestions?.map(\.candidate.tabId), testCase.expectedIDs, testCase.text)
            XCTAssertEqual(fixture.textView.text, testCase.text)
            XCTAssertEqual(fixture.textView.selectedRange, originalSelection)
        }
        XCTAssertTrue(fixture.attachmentAttempts.isEmpty)
    }

    func testWhenQueryContainsSpacesThenShowsOnlyMatchingUnattachedTabs() async {
        let fixture = MentionFixture()
        let candidate = MultiTabAttachmentCandidate(tabId: "new-york", title: "New York City", url: fixture.candidate.url)
        fixture.candidates.append(candidate)
        fixture.textView.text = "@new york"
        fixture.textView.selectedRange = NSRange(location: (fixture.textView.text as NSString).length, length: 0)

        await presentSuggestions(fixture)

        XCTAssertEqual(fixture.suggestions?.map(\.candidate.tabId), [candidate.tabId])
        XCTAssertEqual(fixture.suggestions?.map(\.isEnabled), [true])
        let originalSelection = fixture.textView.selectedRange

        fixture.selectedIDs = [candidate.tabId]
        fixture.controller.refresh()

        XCTAssertNil(fixture.suggestions)
        XCTAssertEqual(fixture.textView.text, "@new york")
        XCTAssertEqual(fixture.textView.selectedRange, originalSelection)

        fixture.selectedIDs = []
        fixture.controller.refresh()

        XCTAssertEqual(fixture.suggestions?.map(\.candidate.tabId), [candidate.tabId])
        XCTAssertTrue(fixture.attachmentAttempts.isEmpty)
    }

    private func presentSuggestions(_ fixture: MentionFixture) async {
        let presented = expectation(description: "Suggestions presented")
        fixture.onUpdate = { if $0 != nil { presented.fulfill() } }
        fixture.controller.textDidChange(in: fixture.textView)
        await fulfillment(of: [presented], timeout: 1)
        fixture.onUpdate = nil
    }
}

@MainActor
private final class MentionFixture {
    let candidate = MultiTabAttachmentCandidate(tabId: "wiki", title: "Wikipedia", url: URL(string: "https://wikipedia.org")!)
    let textView = MentionTestTextView()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    var controller: MultiTabMentionController!
    var candidates: [MultiTabAttachmentCandidate] = []
    var selectedIDs: Set<TabUID> = []
    var allowsAttachment = true
    var acceptsAttachment = true
    var attachmentAttempts: [TabUID] = []
    var candidateReadCount = 0
    var suggestions: [MultiTabMentionController.Suggestion]?
    var onUpdate: (([MultiTabMentionController.Suggestion]?) -> Void)?

    init() {
        candidates = [candidate]
        window.addSubview(textView)
        controller = MultiTabMentionController(environment: .init(
            isEnabled: { true },
            tabs: { [unowned self] in
                candidateReadCount += 1
                return candidates
            },
            attachedTabIds: { [unowned self] in selectedIDs },
            canAttach: { [unowned self] _ in allowsAttachment },
            attachTab: { [unowned self] candidate in
                attachmentAttempts.append(candidate.tabId)
                guard acceptsAttachment else { return false }
                selectedIDs.insert(candidate.tabId)
                return true
            }
        ))
        controller.onSuggestionsChanged = { [weak self] in
            self?.suggestions = $0
            self?.onUpdate?($0)
        }
    }

    func setText(_ text: String) {
        textView.text = text
        let tokenRange = (text as NSString).range(of: "@wiki")
        textView.selectedRange = NSRange(location: NSMaxRange(tokenRange), length: 0)
    }
}

/// Uses real text editing without presenting the system keyboard in unit tests.
@MainActor
final class MentionTestTextView: UITextView {
    override var isFirstResponder: Bool { true }
}
