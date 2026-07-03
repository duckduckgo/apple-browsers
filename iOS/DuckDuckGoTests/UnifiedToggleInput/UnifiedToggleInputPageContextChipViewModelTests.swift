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

    func test_clearAttached_hidesChipAndOffersAttach() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        sut.clearAttached()
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_autoAttachOff_navigationAway_invokesRemoveCallback() {
        // A delivered attachment cleared on nav-away must propagate via onRemoveActionRequested so stale context isn't kept.
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
        // — the user must re-attach via the "Ask About Page" menu item.
        let attachedUrl = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: attachedUrl))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: attachedUrl))
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)

        originatingURL.send(URL(string: attachedUrl))
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
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

    func test_visibility_manual_coldStart_noCarryOver_hiddenOffersAttach() {
        // Fresh chat, no carry-over → chip hidden; attach offered via the "Ask About Page" menu item.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_visibility_manual_coldStart_carryOverMatchingURL_hidden() {
        // 2. Open chat with carry-over matching current URL → hide (FE already has it).
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_visibility_manual_attachLands_visibleAttachedAsFeedback() {
        // 3. User attaches via the menu, host pushes the collected context. Show .attached as
        // feedback so the user sees what they just attached, until they submit.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertFalse(sut.isVisible)

        sut.setAttached(makeContext(title: "Cat", url: url))
        XCTAssertTrue(sut.isVisible)
        XCTAssertEqualState(sut.state, .attached(title: "Cat", favicon: nil))
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_visibility_manual_pendingAttachment_navigateAway_isRemoved() {
        // Manual mode: navigating away removes the attachment even when pending/unsent, and the clear propagates.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url), initialAttachmentDeliveryState: .pendingSubmit)
        XCTAssertTrue(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertEqual(removeCalls, 1)
        XCTAssertFalse(sut.isVisible)
        XCTAssertNil(sut.attachedContext)
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

    func test_visibility_manual_navigateAway_hiddenOffersAttach() {
        // 4. Navigate away → manual clears attachment → chip hidden; attach offered for the new page.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)

        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Dog"))
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_visibility_manual_userDetachesViaX_hiddenOffersAttach() {
        // After X-tap (clearAttached) → no attachment → chip hidden; attach still offered.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertFalse(sut.isVisible)

        sut.clearAttached()
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
    }

    // MARK: - Visibility (auto mode)

    func test_visibility_auto_optedOutInHalfSheet_hiddenOffersAttach() {
        // Auto mode + opted out at the half-sheet (no carry-over) → chip hidden; attach offered.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
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

    func test_visibility_auto_userDetachesViaX_hiddenOffersAttach() {
        // Auto mode + X-tap after an attachment → chip hidden; attach offered to re-attach.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))

        sut.clearAttached()
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_visibility_auto_attachThenSubmitThenDetach_hiddenOffersAttach() {
        // After auto-attach + submit + X-tap, the chip stays hidden and attach is offered.
        autoAttachEnabled = true
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT()

        sut.setAttached(makeContext(title: "Cat", url: url))
        sut.markPromptSubmitted()
        XCTAssertFalse(sut.isVisible)

        sut.clearAttached()
        XCTAssertFalse(sut.isVisible)
        XCTAssertTrue(sut.canAttachPageContext)
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

    // MARK: - canAttachPageContext (drives the "Ask About Page" menu item)

    func test_canAttachPageContext_noOriginatingURL_isFalse() {
        makeSUT()
        XCTAssertFalse(sut.canAttachPageContext)
    }

    func test_canAttachPageContext_originatingURLNoAttachment_isTrue() {
        originatingURL.send(URL(string: "https://en.wikipedia.org/wiki/Cat"))
        makeSUT()
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_canAttachPageContext_whileAttached_isTrue() {
        // Always available in the contextual scenario — tapping re-collects + replaces with the latest.
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertTrue(sut.canAttachPageContext)
    }

    func test_canAttachPageContext_staysTrueThroughAttachAndClear() {
        let url = "https://en.wikipedia.org/wiki/Cat"
        originatingURL.send(URL(string: url))
        makeSUT(initialAttachedContext: makeContext(title: "Cat", url: url))
        XCTAssertTrue(sut.canAttachPageContext)

        sut.clearAttached()
        XCTAssertTrue(sut.canAttachPageContext)
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
