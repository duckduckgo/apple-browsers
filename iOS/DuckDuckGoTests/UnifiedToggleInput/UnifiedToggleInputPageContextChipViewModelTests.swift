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

    // MARK: - State transitions

    func test_initial_attachedAndOriginatingMatches_isAttached() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Wikipedia", url: url))
        XCTAssertEqualState(sut.state, .attached(title: "Wikipedia", favicon: nil))
    }

    func test_setAttached_withMatchingOriginating_flipsToAttached() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_setAttachedNil_flipsToPlaceholder() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        sut.setAttached(nil)
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

    func test_autoAttachOn_originatingURLChangesAwayThenBack_attachmentPreservedInternally() {
        // With auto-attach ON, navigating away does NOT clear the underlying attachment —
        // the host is responsible for re-attaching with the new page's context. Returning to
        // the original page restores the attached display.
        autoAttachEnabled = true
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        // Auto mode shows the attached site through the transition.
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_autoAttachOff_originatingURLAwayThenBack_doesNotRestoreAttached() {
        // Manual mode: leaving the page clears the attachment. Navigating back does NOT restore
        // — the user must tap the placeholder to re-attach.
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqualState(sut.state, .placeholder)

        originatingURL.send(URL(string: attachedUrl))
        XCTAssertEqualState(sut.state, .placeholder)
    }

    // MARK: - Tap handling

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

    // MARK: - Visibility (manual mode)

    func test_visibility_manual_coldStart_noCarryOver_visiblePlaceholder() {
        // 1. Open chat fresh on page X with no carry-over → show placeholder so user can attach.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_visibility_manual_coldStart_carryOverMatchingURL_hidden() {
        // 2. Open chat with carry-over matching current URL → hide (FE already has it).
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_visibility_manual_attachLands_visibleAttachedAsFeedback() {
        // 3. User taps placeholder, host pushes the collected context. Show .attached as
        // feedback so the user sees what they just attached, until they submit.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertTrue(sut.isVisible)

        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_visibility_manual_afterSubmit_hidden() {
        // After submit with a matching attachment, chip goes silent — FE keeps including the
        // context with every subsequent prompt; on-screen UI would be redundant.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertTrue(sut.isVisible)

        sut.markPromptSubmitted()
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_visibility_manual_reAttachAfterSubmit_visibleAgain() {
        // Detach and re-attach restarts the "needs feedback" cycle — the new attachment is a
        // distinct user action and should be visible until the next submit.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: url))
        sut.markPromptSubmitted()
        XCTAssertFalse(sut.isVisible)

        sut.setAttached(nil)
        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertTrue(sut.isVisible)
    }

    func test_visibility_manual_navigateAway_visiblePlaceholder() {
        // 4. Navigate away → manual clears attachment → show placeholder for the new page.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_visibility_manual_userDetachesViaX_visiblePlaceholder() {
        // 5. After X-tap (host calls setAttached(nil)) → no attachment → show placeholder so
        // the user can re-attach if they change their mind.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)

        sut.setAttached(nil)
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    // MARK: - Visibility (auto mode)

    func test_visibility_auto_coldStart_noCarryOver_hidden() {
        // 6. Auto mode + cold start with no carry-over → hidden, waiting for auto-attach to
        // land. Otherwise we'd flash a placeholder before the attachment arrives.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertFalse(sut.isVisible)
    }

    func test_visibility_auto_coldStart_carryOverMatchingURL_hidden() {
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)
    }

    func test_visibility_auto_navigateAway_visibleAttached() {
        // Auto preserves the attachment through navigation; show the attached site through the
        // transition rather than flashing placeholder.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_visibility_auto_reAttachLands_visibleUntilSubmit() {
        // After the host re-attaches with the new URL's context, that's a fresh attachment —
        // show it as feedback until the user submits a prompt for this page.
        autoAttachEnabled = true
        let originalURL = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: originalURL))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: originalURL))

        let newURL = "https://en.wikipedia.org/wiki/Dog"
        originatingURL.send(URL(string: newURL))
        sut.setAttached(makeContext(title: "Dog", url: newURL))

        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Dog", favicon: nil))

        sut.markPromptSubmitted()
        XCTAssertFalse(sut.isVisible)
    }

    func test_visibility_auto_userDetachesViaX_visiblePlaceholder() {
        // Auto mode + user X-taps after at least one attachment in the session → show
        // placeholder so they can re-attach manually. (The initial cold-start wait is the
        // only time we hide auto + no attachment.)
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))

        sut.setAttached(nil)
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_visibility_auto_coldStart_thenAutoAttachLands_thenDetach_visiblePlaceholder() {
        // Cold start in auto: hidden. After auto-attach lands and the user X-taps, the
        // placeholder must appear — the initial-wait hide rule does not re-engage post-detach.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertFalse(sut.isVisible)

        sut.setAttached(makeContext(title: "Cat", url: url))
        sut.markPromptSubmitted()
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
