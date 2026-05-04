//
//  UnifiedToggleInputPageContextChipViewModelTests.swift
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
import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputPageContextChipViewModelTests: XCTestCase {

    private var originatingURL: CurrentValueSubject<URL?, Never>!
    private var sut: UnifiedToggleInputPageContextChipViewModel!
    private var attachCalls: [URL] = []
    private var removeCalls: Int = 0
    private var autoAttachEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        originatingURL = .init(nil)
        attachCalls = []
        removeCalls = 0
        autoAttachEnabled = false
    }

    private func makeSUT(initialAttachedContext: AIChatPageContext? = nil) {
        sut = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            initialAttachedContext: initialAttachedContext,
            isAutoAttachEnabled: { [weak self] in self?.autoAttachEnabled ?? false }
        )
        sut.onAttachActionRequested = { [weak self] url in self?.attachCalls.append(url) }
        sut.onRemoveActionRequested = { [weak self] in self?.removeCalls += 1 }
    }

    func test_initial_noContext_isPlaceholder() {
        makeSUT()
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_initial_attachedAndOriginatingMatches_isAttached() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Wikipedia", url: url))
        XCTAssertEqualState(sut.state, .attached(title: "Wikipedia", favicon: nil))
    }

    func test_initial_attachedButOriginatingDifferent_isPlaceholder() {
        originatingURL.send(URL(string: "https://other.example.com"))
        makeSUT(initialAttachedContext: makeContext(title: "Wikipedia", url: "https://en.wikipedia.org/wiki/Cat"))
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_setAttached_withMatchingOriginating_flipsToAttached() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_setAttached_withNonMatchingOriginating_staysPlaceholder() {
        originatingURL.send(URL(string: "https://other.example.com"))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: "https://en.wikipedia.org/wiki/Cat"))
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_setAttachedNil_flipsToPlaceholder() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        sut.setAttached(nil)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_originatingURLChange_awayFromAttachedPage_displayFlipsToPlaceholder() {
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_autoAttachOff_navigationAway_invokesRemoveCallback() {
        // Regression: nav-away clearing must propagate through onRemoveActionRequested so the
        // host clears the FE-side cached page context. Otherwise the next prompt would ship
        // stale context even though the chip displays placeholder.
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))
        XCTAssertEqual(removeCalls, 0)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqual(removeCalls, 1)
    }

    func test_autoAttachOn_navigationAway_doesNotInvokeRemoveCallback() {
        // With auto-attach ON, the attachment is preserved while the host re-collects, so
        // the remove callback must NOT fire on nav-away.
        autoAttachEnabled = true
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqual(removeCalls, 0)
    }

    func test_autoAttachOn_originatingURLChangesAway_attachmentPreservedInternally() {
        // With auto-attach ON, navigating away does NOT clear the underlying attachment —
        // the host is responsible for re-attaching with the new page's context. Returning to
        // the original page restores the attached display.
        autoAttachEnabled = true
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqualState(sut.state, .placeholder)

        originatingURL.send(URL(string: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_originatingURLChange_awayThenBack_doesNotRestoreAttached() {
        // Half-sheet behavior with auto-attach OFF: leaving the page clears the attachment.
        // Navigating back does NOT restore — the user must tap the placeholder to re-attach.
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqualState(sut.state, .placeholder)

        originatingURL.send(URL(string: attachedUrl))
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_tapToAttach_withOriginatingURL_callsOnAttach() {
        makeSUT()
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        sut.tapToAttach()
        XCTAssertEqual(attachCalls, [url])
    }

    func test_tapToAttach_noOriginatingURL_doesNotCallOnAttach() {
        makeSUT()
        sut.tapToAttach()
        XCTAssertTrue(attachCalls.isEmpty)
    }

    func test_tapToRemove_callsOnRemove() {
        makeSUT()
        sut.tapToRemove()
        XCTAssertEqual(removeCalls, 1)
    }

    // MARK: - Visibility

    func test_visibility_noInitialContext_isHiddenInitially() {
        // Same URL, page hasn't changed — chip should be hidden regardless of carry-over.
        makeSUT()
        XCTAssertFalse(sut.isVisible)
    }

    func test_visibility_withInitialContext_isHiddenInitially() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)
    }

    func test_visibility_becomesVisibleOnNavigation() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertTrue(sut.isVisible)
    }

    func test_visibility_staysVisibleAfterSubsequentChanges() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertTrue(sut.isVisible)

        originatingURL.send(URL(string: url))
        XCTAssertTrue(sut.isVisible)
    }

    func test_markPromptSubmitted_hidesChip() {
        // After submit, chip auto-hides — user already saw "this is attached" and committed.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertTrue(sut.isVisible)

        sut.markPromptSubmitted()

        XCTAssertFalse(sut.isVisible)
    }

    func test_markPromptSubmitted_chipReappearsOnNextNavigation() {
        // After submit + nav, chip re-appears so user sees the new attachment context.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        sut.markPromptSubmitted()
        XCTAssertFalse(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Bird"))

        XCTAssertTrue(sut.isVisible)
    }

    func test_visibility_appliesEvenWhenDetached() {
        // Removing the attached context (X tapped) keeps the chip visible as a placeholder
        // so the user can re-attach.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertTrue(sut.isVisible)

        sut.setAttached(nil)
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    // MARK: - Helpers

    private func makeContext(title: String, url: String) -> AIChatPageContext {
        let data = AIChatPageContextData(title: title, favicon: [], url: url, content: "", truncated: false, fullContentLength: 0)
        return AIChatPageContext(contextData: data, favicon: nil)
    }

    private func XCTAssertEqualState(_ lhs: AIChatContextChipView.State, _ rhs: AIChatContextChipView.State, file: StaticString = #filePath, line: UInt = #line) {
        switch (lhs, rhs) {
        case (.placeholder, .placeholder):
            return
        case (.attached(let lt, _), .attached(let rt, _)) where lt == rt:
            return
        default:
            XCTFail("State mismatch: \(lhs) vs \(rhs)", file: file, line: line)
        }
    }
}
