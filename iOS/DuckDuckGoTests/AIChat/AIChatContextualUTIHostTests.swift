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
import Core
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
        initialAttachmentDeliveryState: PageContextAttachmentDeliveryState = .delivered,
        attachMoreTabsFeature: AIChatContextualAttachMoreTabsFeatureProviding = AIChatContextualAttachMoreTabsFeature(),
        tabAttachmentSource: MultiTabAttachmentSource? = nil,
        isCurrentPageAttachInProgress: @escaping () -> Bool = { false }
    ) {
        sut = AIChatContextualUTIHost(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            initialAttachedContext: initialAttachedContext,
            initialAttachmentDeliveryState: initialAttachmentDeliveryState,
            hasActiveChat: { [weak self] in self?.hasActiveChat ?? false },
            isAutoAttachEnabled: { [weak self] in self?.autoAttachEnabled ?? false },
            isFireTab: false,
            attachMoreTabsFeature: attachMoreTabsFeature,
            tabAttachmentSource: tabAttachmentSource,
            isCurrentPageAttachInProgress: isCurrentPageAttachInProgress
        )
    }

    func testMultiTabProviderIsNotInvokedWhileFeatureDisabled() {
        makeSUT(attachMoreTabsFeature: AIChatContextualAttachMoreTabsFeature(
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []), aiChatSettings: MockAIChatSettingsProvider()))
        sut.attachedTabContextsProvider = {
            XCTFail("Disabled feature must not invoke the attachment provider")
            return nil
        }
        let script = makeTestUserScript()
        sut.bindToUserScript(script)

        XCTAssertNil(script.attachedTabContextsProvider?())
    }

    func testMultiTabProviderObservesFeatureChangesAfterBinding() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        makeSUT(attachMoreTabsFeature: AIChatContextualAttachMoreTabsFeature(
            featureFlagger: flagger, aiChatSettings: MockAIChatSettingsProvider()))
        var requestCount = 0
        sut.attachedTabContextsProvider = {
            requestCount += 1
            return MultiTabAttachmentRequest(contexts: { [] }, didConsume: {})
        }
        let script = makeTestUserScript()
        sut.bindToUserScript(script)
        XCTAssertNil(script.attachedTabContextsProvider?())

        flagger.enabledFeatureFlags = [.aiChatContextualAttachMoreTabs]
        XCTAssertNotNil(script.attachedTabContextsProvider?())
        XCTAssertEqual(requestCount, 1)

        flagger.enabledFeatureFlags = []
        XCTAssertNil(script.attachedTabContextsProvider?())
        XCTAssertEqual(requestCount, 1)
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

    func test_duckAIPromptSubmission_forwardsContextualOrigin() {
        var submittedOrigins: [AIChatEntryPointSource?] = []
        makeSUT()
        sut.onDuckAIPromptSubmitted = { submittedOrigins.append($0) }

        sut.unifiedToggleInputDidSubmitDuckAIPrompt(origin: .contextualChat)

        XCTAssertEqual(submittedOrigins, [.contextualChat])
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

        sut.unmount(from: first)
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
        sut.unmount(from: UIViewController())
    }

    /// A dismissal animating out finishes after the next surface may already have mounted the input. Taking
    /// it away then would leave that surface without its bar.
    func test_unmountFromAStaleParent_leavesTheCurrentMountAlone() {
        makeSUT()
        let stale = UIViewController()
        let current = UIViewController()

        _ = sut.mount(in: stale)
        let inputView = sut.mount(in: current)

        sut.unmount(from: stale)

        XCTAssertTrue(inputView.isDescendant(of: current.view))
        XCTAssertEqual(current.children.count, 1)
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

    func testTabMenuSharesCurrentPagePendingAndDeliveredState() throws {
        let url = URL(string: "https://example.com/page")!
        let context = makeContext(title: "Current page", url: url.absoluteString)
        let source = makeTabSource(url: url)
        makeSUT(initialAttachedContext: context, initialAttachmentDeliveryState: .delivered,
                attachMoreTabsFeature: FixedTabAttachmentFeature(state: .available(maximumTabAttachmentCount: 1)),
                tabAttachmentSource: source)
        let parent = UIViewController()
        sut.mount(in: parent)
        let input = try XCTUnwrap(parent.children.first as? UnifiedToggleInputViewController)

        var actions = try recentTabActions(in: input)
        XCTAssertEqual(actions.map(\.state), [.off, .off])
        XCTAssertFalse(actions[1].attributes.contains(.disabled))

        sut.setAttachedContext(context, deliveryState: .pendingSubmit)
        actions = try recentTabActions(in: input)
        XCTAssertEqual(actions.map(\.state), [.on, .off])
        XCTAssertTrue(actions[1].attributes.contains(.disabled))

        sut.clearAttachedContext()
        actions = try recentTabActions(in: input)
        XCTAssertEqual(actions.map(\.state), [.off, .off])
        XCTAssertFalse(actions[1].attributes.contains(.disabled))
    }

    func testTabMenuReservesCurrentPageSlotDuringExistingCollection() throws {
        let url = URL(string: "https://example.com/page")!
        var isCollecting = true
        makeSUT(attachMoreTabsFeature: FixedTabAttachmentFeature(state: .available(maximumTabAttachmentCount: 1)),
                tabAttachmentSource: makeTabSource(url: url),
                isCurrentPageAttachInProgress: { isCollecting })
        let parent = UIViewController()
        sut.mount(in: parent)
        let input = try XCTUnwrap(parent.children.first as? UnifiedToggleInputViewController)

        var actions = try recentTabActions(in: input)
        XCTAssertEqual(actions[0].state, .on)
        XCTAssertTrue(actions[1].attributes.contains(.disabled))

        isCollecting = false
        sut.refreshPageContextAttachability()
        actions = try recentTabActions(in: input)
        XCTAssertEqual(actions[0].state, .off)
        XCTAssertFalse(actions[1].attributes.contains(.disabled))
    }

    func testDisabledTabFeaturePreservesCurrentPageActionWithoutReadingTabs() throws {
        let source = MultiTabAttachmentSource(currentTabID: "current", mode: .normal, tabsProvider: {
            XCTFail("Disabled multi-tab feature must not request candidates")
            return []
        })
        makeSUT(attachMoreTabsFeature: FixedTabAttachmentFeature(state: .unavailable), tabAttachmentSource: source)
        let parent = UIViewController()
        sut.mount(in: parent)
        let input = try XCTUnwrap(parent.children.first as? UnifiedToggleInputViewController)
        let menu = try XCTUnwrap(input.attachmentMenu)
        let actions = menu.children.compactMap { $0 as? UIAction }

        XCTAssertTrue(actions.contains { $0.title == UserText.aiChatAttachmentOptionAskAboutPage && !$0.attributes.contains(.disabled) })
        XCTAssertFalse(actions.contains { $0.title == UserText.aiChatAttachmentOptionAddTabs })
    }

    private func makeTabSource(url: URL) -> MultiTabAttachmentSource {
        let tabs = [Tab(uid: "current", link: Link(title: "Current page", url: url), fireTab: false),
                    Tab(uid: "other", link: Link(title: "Other page", url: url), fireTab: false)]
        return MultiTabAttachmentSource(currentTabID: "current", mode: .normal, tabsProvider: { tabs })
    }

    private func recentTabActions(in input: UnifiedToggleInputViewController) throws -> [UIAction] {
        let menu = try XCTUnwrap(input.attachmentMenu)
        let recent = try XCTUnwrap(menu.children.first as? UIMenu)
        return recent.children.compactMap { $0 as? UIAction }
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

private struct FixedTabAttachmentFeature: AIChatContextualAttachMoreTabsFeatureProviding {
    let state: AIChatContextualAttachMoreTabsState
}
