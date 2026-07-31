//
//  AIChatContextualUTIHostTests.swift
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
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatContextualUTIHostTests: XCTestCase {

    private var originatingURL: CurrentValueSubject<URL?, Never>!
    private var autoAttachEnabled = false
    private var hasActiveChat = false
    private var sut: AIChatContextualUTIHost!

    override func setUp() async throws {
        try await super.setUp()
        originatingURL = .init(nil)
        autoAttachEnabled = false
        hasActiveChat = false
    }

    override func tearDown() async throws {
        sut = nil
        originatingURL = nil
        try await super.tearDown()
    }

    private func makeSUT(
        initialAttachedContext: AIChatPageContext? = nil,
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered
    ) {
        sut = AIChatContextualUTIHost(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            initialAttachedContext: initialAttachedContext,
            initialAttachmentDeliveryState: initialAttachmentDeliveryState,
            hasActiveChat: { [weak self] in self?.hasActiveChat ?? false },
            isAutoAttachEnabled: { [weak self] in self?.autoAttachEnabled ?? false },
            isFireTab: false
        )
    }

    func test_chipAttachAction_firesAttachCallback() {
        let url = URL(string: "https://example.com/a")!
        var attachCallCount = 0
        makeSUT()
        sut.onAttachRequested = { attachCallCount += 1 }
        originatingURL.send(url)

        sut.chipViewModel.tapToAttach()

        XCTAssertEqual(attachCallCount, 1)
    }

    func test_chipAttachAction_withoutOriginatingURL_stillFiresAttachCallback() {
        var attachCallCount = 0
        makeSUT()
        sut.onAttachRequested = { attachCallCount += 1 }

        sut.chipViewModel.tapToAttach()

        XCTAssertEqual(attachCallCount, 1)
    }

    func test_aiVoiceChatRequest_firesVoiceCallback() {
        var voiceCallCount = 0
        makeSUT()
        sut.onAIVoiceChatRequested = { voiceCallCount += 1 }

        sut.unifiedToggleInputDidRequestAIVoiceChat()

        XCTAssertEqual(voiceCallCount, 1)
    }

    func test_chipRemoveAction_firesRemoveCallbackOnly() {
        let url = URL(string: "https://example.com/a")!
        var removeCallCount = 0
        originatingURL.send(url)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: url.absoluteString))
        sut.onRemoveRequested = { removeCallCount += 1 }

        sut.chipViewModel.tapToRemove()

        XCTAssertEqual(removeCallCount, 1)
    }

    func test_setAttachedContext_updatesChipPresentation() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        makeSUT()

        sut.setAttachedContext(makeContext(title: "Page A", url: url.absoluteString))

        XCTAssertEqualState(sut.chipViewModel.state, .attached(title: "Page A", favicon: nil))
        XCTAssertEqual(sut.attachedContextURL, url)
    }

    func test_clearAttachedContext_updatesChipPresentation() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: url.absoluteString))

        sut.clearAttachedContext()

        XCTAssertEqualState(sut.chipViewModel.state, .placeholder)
        XCTAssertNil(sut.attachedContextURL)
    }

    func test_showAttachAffordanceKeepsPlaceholderHiddenWithoutClearingDeliveredAttachment() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: url.absoluteString), initialAttachmentDeliveryState: .delivered)

        sut.showAttachAffordance()

        XCTAssertEqualState(sut.chipViewModel.state, .placeholder)
        XCTAssertFalse(sut.chipViewModel.isVisible)
        XCTAssertEqual(sut.attachedContextURL, url)
        XCTAssertNil(sut.chipViewModel.pendingAttachedContextData)
    }

    func test_showAttachAffordanceDoesNotOverridePendingAttachment() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: url.absoluteString), initialAttachmentDeliveryState: .pendingSubmit)

        sut.showAttachAffordance()

        XCTAssertEqualState(sut.chipViewModel.state, .attached(title: "Page A", favicon: nil))
        XCTAssertTrue(sut.chipViewModel.isVisible)
        XCTAssertEqual(sut.attachedContextURL, url)
        XCTAssertEqual(sut.chipViewModel.pendingAttachedContextData?.url, url.absoluteString)
    }

    func test_setAttachedContextWithSameURLAfterDelivered_makesContextPendingAgain() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        let context = makeContext(title: "Page A", url: url.absoluteString)
        makeSUT(initialAttachedContext: context, initialAttachmentDeliveryState: .delivered)

        XCTAssertNil(sut.chipViewModel.pendingAttachedContextData)

        sut.setAttachedContext(context)

        XCTAssertEqual(sut.chipViewModel.pendingAttachedContextData?.url, url.absoluteString)
        XCTAssertEqualState(sut.chipViewModel.state, .attached(title: "Page A", favicon: nil))
    }

    func test_notifyPromptDelivered_firesOnPromptDeliveredCallback() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: url.absoluteString), initialAttachmentDeliveryState: .pendingSubmit)
        var deliveredCount = 0
        sut.onPromptDelivered = { deliveredCount += 1 }

        sut.notifyPromptDelivered()

        XCTAssertEqual(deliveredCount, 1)
    }

    func test_prepareForNewChat_clearsAttachedContextPresentation() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: url.absoluteString))

        sut.prepareForNewChat()

        XCTAssertEqualState(sut.chipViewModel.state, .placeholder)
        XCTAssertNil(sut.attachedContextURL)
    }

    func test_autoAttachOn_didCommitURLChangeAlone_doesNotFireAttachCallback() {
        autoAttachEnabled = true
        var didRequestAttach = false
        makeSUT()
        sut.onAttachRequested = { didRequestAttach = true }

        originatingURL.send(URL(string: "https://example.com/b"))

        XCTAssertFalse(didRequestAttach)
    }

    func test_autoAttachOff_navigationAwayKeepsManualAttachmentSticky() {
        let pageAURL = URL(string: "https://example.com/a")!
        let pageBURL = URL(string: "https://example.com/b")!
        var removeCallCount = 0
        originatingURL.send(pageAURL)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: pageAURL.absoluteString), initialAttachmentDeliveryState: .pendingSubmit)
        sut.onRemoveRequested = { removeCallCount += 1 }

        originatingURL.send(pageBURL)

        XCTAssertEqual(removeCallCount, 0)
        XCTAssertEqualState(sut.chipViewModel.state, .attached(title: "Page A", favicon: nil))
        XCTAssertEqual(sut.attachedContextURL, pageAURL)
    }

    func test_unmountThenMountElsewhere_leavesExactlyOneParent() {
        makeSUT()
        let first = UIViewController()
        let second = UIViewController()

        let firstView = sut.mount(in: first)
        XCTAssertTrue(firstView.isDescendant(of: first.view))
        XCTAssertEqual(first.children.count, 1)

        sut.unmount()
        XCTAssertTrue(first.children.isEmpty)
        XCTAssertNil(firstView.superview)

        let secondView = sut.mount(in: second)
        XCTAssertTrue(secondView.isDescendant(of: second.view))
        XCTAssertEqual(second.children.count, 1)
        XCTAssertTrue(first.children.isEmpty)
    }

    func test_mountTwiceInSameParent_doesNotDuplicate() {
        makeSUT()
        let parent = UIViewController()

        sut.mount(in: parent)
        sut.mount(in: parent)

        XCTAssertEqual(parent.children.count, 1)
    }

    func test_unmountWithoutMount_doesNothing() {
        makeSUT()
        sut.unmount()
    }

    /// Freezing is what lets a dismissal own the surface's motion, so it has to hand over the position the
    /// keyboard guide was holding — not shift it as the constraint is swapped.
    func test_freezeInputPosition_leavesTheInputExactlyWhereItWas() {
        makeSUT()
        let parent = UIViewController()
        parent.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let inputView = sut.mount(in: parent)
        parent.view.layoutIfNeeded()
        let before = inputView.frame

        sut.freezeInputPosition()
        parent.view.layoutIfNeeded()

        XCTAssertEqual(inputView.frame, before)
    }

    func test_freezeInputPositionTwice_stillLeavesItWhereItWas() {
        makeSUT()
        let parent = UIViewController()
        parent.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let inputView = sut.mount(in: parent)
        parent.view.layoutIfNeeded()
        let before = inputView.frame

        sut.freezeInputPosition()
        sut.freezeInputPosition()
        parent.view.layoutIfNeeded()

        XCTAssertEqual(inputView.frame, before)
    }

    /// A frozen pin belongs to the parent it was measured against. Left behind, the next mount would sit at a
    /// stale position.
    func test_freezeThenRemount_pinsToTheNewParent() {
        makeSUT()
        let first = UIViewController()
        first.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        _ = sut.mount(in: first)
        first.view.layoutIfNeeded()
        sut.freezeInputPosition()

        let second = UIViewController()
        second.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        let inputView = sut.mount(in: second)
        second.view.layoutIfNeeded()

        XCTAssertTrue(inputView.isDescendant(of: second.view))
        XCTAssertEqual(inputView.frame.maxY, second.view.keyboardLayoutGuide.layoutFrame.minY)
    }

    private func makeContext(title: String, url: String) -> AIChatPageContext {
        AIChatPageContext(
            contextData: AIChatPageContextData(
                title: title,
                favicon: [],
                url: url,
                content: "Content for \(title)",
                truncated: false,
                fullContentLength: 12
            ),
            favicon: nil
        )
    }
}

private func XCTAssertEqualState(
    _ actual: AIChatContextChipView.State,
    _ expected: AIChatContextChipView.State,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (actual, expected) {
    case (.placeholder, .placeholder):
        return
    case let (.attached(actualTitle, _), .attached(expectedTitle, _)):
        XCTAssertEqual(actualTitle, expectedTitle, file: file, line: line)
    default:
        XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
    }
}
