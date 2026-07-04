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
    private var attachCalls: Int = 0
    private var removeCalls: Int = 0
    private var autoAttachEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        originatingURL = .init(nil)
        attachCalls = 0
        removeCalls = 0
        autoAttachEnabled = false
    }

    private func makeSUT(
        initialAttachedContext: AIChatPageContext? = nil,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered
    ) {
        sut = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            initialAttachedContext: initialAttachedContext,
            initialAttachmentDeliveryState: initialAttachmentDeliveryState,
            isAutoAttachEnabled: { [weak self] in self?.autoAttachEnabled ?? false }
        )
        sut.onAttachActionRequested = { [weak self] in self?.attachCalls += 1 }
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

    func test_clearAttached_flipsToPlaceholder() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        sut.clearAttached()
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_autoAttachOff_navigationAway_keepsManualPendingAttachmentSticky() {
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl), initialAttachmentDeliveryState: .pendingSubmit)
        XCTAssertEqual(removeCalls, 0)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertTrue(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqual(removeCalls, 0)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertTrue(sut.isVisible)
    }

    func test_autoAttachOff_navigationAway_keepsManualDeliveredAttachmentStickyAndHidden() {
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl), initialAttachmentDeliveryState: .delivered)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertFalse(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertFalse(sut.isVisible)
    }

    func test_showAttachAffordance_preservesDeliveredAttachmentAndShowsPlaceholder() {
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl), initialAttachmentDeliveryState: .delivered)
        XCTAssertFalse(sut.isVisible)

        sut.showAttachAffordance()

        XCTAssertEqualState(sut.state, .placeholder)
        XCTAssertTrue(sut.isVisible)
        XCTAssertNil(sut.pendingAttachedContextData)

        sut.tapToAttach()
        XCTAssertEqual(attachCalls, 1)

        sut.setAttached(makeContext(title: "Dog", url: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqualState(sut.state, .attached(title: "Dog", favicon: nil))
        XCTAssertEqual(sut.pendingAttachedContextData?.url, "https://en.wikipedia.org/wiki/Dog")
    }

    func test_showAttachAffordance_doesNotOverridePendingAttachment() {
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl), initialAttachmentDeliveryState: .pendingSubmit)

        sut.showAttachAffordance()

        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqual(sut.pendingAttachedContextData?.url, attachedUrl)
    }

    func test_autoAttachOn_navigationAway_preservesAttachment() {
        autoAttachEnabled = true
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl), initialAttachmentDeliveryState: .pendingSubmit)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqual(removeCalls, 0)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertTrue(sut.isVisible)
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

    func test_autoAttachOff_originatingURLAwayThenBack_keepsManualAttachmentSticky() {
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl), initialAttachmentDeliveryState: .pendingSubmit)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    // MARK: - Tap handling

    func test_tapToAttach_withOriginatingURL_callsOnAttach() {
        makeSUT()
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        sut.tapToAttach()
        XCTAssertEqual(attachCalls, 1)
    }

    func test_tapToAttach_noOriginatingURL_callsOnAttach() {
        makeSUT()
        sut.tapToAttach()
        XCTAssertEqual(attachCalls, 1)
    }

    func test_tapToRemove_clearsChipAndCallsOnRemove() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        sut.tapToRemove()

        XCTAssertEqualState(sut.state, .placeholder)
        XCTAssertTrue(sut.isVisible)
        XCTAssertNil(sut.pendingAttachedContextData)
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

        sut.clearAttached()
        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertTrue(sut.isVisible)
    }

    func test_visibility_manual_navigateAway_keepsAttachedState() {
        // Manual mode is sticky: navigation does not clear or replace an existing attachment.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url), initialAttachmentDeliveryState: .pendingSubmit)
        XCTAssertTrue(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_visibility_manual_userDetachesViaX_visiblePlaceholder() {
        // 5. After X-tap (host calls clearAttached()) → no attachment → show placeholder so
        // the user can re-attach if they change their mind.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)

        sut.clearAttached()
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    // MARK: - Visibility (auto mode)

    func test_visibility_auto_optedOutInHalfSheet_visiblePlaceholder() {
        // Auto mode + user opted out at the half-sheet (no carry-over) → show placeholder.
        // The half-sheet is where the user exercises their attach/skip agency; the chat is
        // not a "waiting for first attach" surface, so we never hide an empty auto state.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_visibility_auto_coldStart_carryOverMatchingURL_hidden() {
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)
    }

    func test_visibility_auto_navigateAwayWithDeliveredAttachment_staysHiddenUntilNewContextLands() {
        // Delivered attachments are already silent. When auto-attach starts collecting a new
        // page, don't briefly resurface the old page chip during the load transition.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
    }

    func test_visibility_auto_navigateAwayWithPendingAttachment_visibleAttached() {
        // Pending attachments still show through navigation so the user doesn't lose feedback
        // for an attachment they have not submitted yet.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url), initialAttachmentDeliveryState: .pendingSubmit)

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

        sut.clearAttached()
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    func test_visibility_auto_attachThenSubmitThenDetach_returnsToPlaceholder() {
        // After auto-attach lands and the user submits, then X-taps, the placeholder reappears
        // so they can re-attach manually.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()

        sut.setAttached(makeContext(title: "Cat", url: url))
        sut.markPromptSubmitted()
        XCTAssertFalse(sut.isVisible)

        sut.clearAttached()
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .placeholder)
    }

    // MARK: - Pending attached context (provider for prompt payload)

    func test_pendingAttachedContextData_noAttachment_returnsNil() {
        makeSUT()
        XCTAssertNil(sut.pendingAttachedContextData)
    }

    func test_pendingAttachedContextData_afterSetAttached_returnsContextData() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertEqual(sut.pendingAttachedContextData?.title, "Cat")
    }

    func test_pendingAttachedContextData_afterMarkPromptSubmitted_returnsNil() {
        // Once the chip flips to `.delivered`, every
        // subsequent prompt must ship `pageContext: nil` — otherwise duck.ai renders a
        // "Page content from..." attribution beneath each follow-up prompt.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: url))
        sut.markPromptSubmitted()
        XCTAssertNil(sut.pendingAttachedContextData)
    }

    func test_pendingAttachedContextData_initialDelivered_returnsNil() {
        // Carry-over from half-sheet arrives `.delivered` — the FE already has it for the
        // initial submission, so the next prompt's payload must not duplicate it.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(
            initialAttachedContext: makeContext(title: "Cat", url: url),
            initialAttachmentDeliveryState: .delivered
        )
        XCTAssertNil(sut.pendingAttachedContextData)
    }

    func test_pendingAttachedContextData_initialPending_returnsContextData() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(
            initialAttachedContext: makeContext(title: "Cat", url: url),
            initialAttachmentDeliveryState: .pendingSubmit
        )
        XCTAssertEqual(sut.pendingAttachedContextData?.title, "Cat")
    }

    func test_pendingAttachedContextData_reAttachAfterSubmit_returnsContextData() {
        // Detach + re-attach is a fresh user action that restarts the pending cycle — the next
        // prompt should carry the newly attached context.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        sut.setAttached(makeContext(title: "Cat", url: url))
        sut.markPromptSubmitted()
        XCTAssertNil(sut.pendingAttachedContextData)

        sut.clearAttached()
        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertEqual(sut.pendingAttachedContextData?.title, "Cat")
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
