//
//  AIChatContextualSuggestionsStripTests.swift
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

import Combine
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatContextualSuggestionsStripTests: XCTestCase {

    private var viewState: CurrentValueSubject<SheetViewState, Never>!
    private var anchor: AnchorStub!
    private var parent: UIViewController!
    private var sut: AIChatContextualSuggestionsStrip!

    override func setUp() async throws {
        try await super.setUp()
        viewState = .init(makeViewState(suggestions: []))
        anchor = AnchorStub()
        parent = UIViewController()
        parent.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        parent.view.addSubview(anchor.inputView)
        sut = AIChatContextualSuggestionsStrip(controller: makeChips(), input: anchor)
        sut.bind(to: viewState.eraseToAnyPublisher())
    }

    override func tearDown() async throws {
        sut = nil
        parent = nil
        anchor = nil
        viewState = nil
        try await super.tearDown()
    }

    // MARK: - Entrance

    /// Page context attaches before suggestions resolve, so the first batches legitimately carry
    /// nothing to animate.
    func test_anEmptyBatchDoesNotConsumeTheEntrance() {
        sut.embed(in: parent, style: .floating)

        send(suggestions: [])
        XCTAssertFalse(sut.hasShownForTesting)

        send(suggestions: [makeSuggestion(id: "s1")])
        XCTAssertTrue(sut.hasShownForTesting)
    }

    func test_theEntranceIsConsumedByTheFirstBatchWithChips() {
        sut.embed(in: parent, style: .floating)
        send(suggestions: [makeSuggestion(id: "s1")])
        XCTAssertTrue(sut.hasShownForTesting)

        send(suggestions: [makeSuggestion(id: "s1"), makeSuggestion(id: "s2")])

        XCTAssertTrue(sut.hasShownForTesting)
        XCTAssertEqual(sut.chipCountForTesting, 2)
    }

    /// The next surface takes it blank, un-slid and with its own entrance to play — rather than
    /// inheriting the previous surface's chips at full opacity.
    func test_detachingLeavesTheStripBlank() {
        sut.embed(in: parent, style: .floating)
        send(suggestions: [makeSuggestion(id: "s1")])
        sut.containerView.transform = CGAffineTransform(translationX: 0, y: -40)
        XCTAssertTrue(sut.hasShownForTesting)

        sut.detach(from: parent)

        XCTAssertFalse(sut.hasShownForTesting)
        XCTAssertEqual(sut.containerView.alpha, 0)
        XCTAssertEqual(sut.containerView.transform, .identity)
        XCTAssertEqual(sut.chipCountForTesting, 0)
    }

    // MARK: - Style

    func test_theFloatingStyleCarriesQuickActions() {
        sut.embed(in: parent, style: .floating)

        send(suggestions: [makeSuggestion(id: "s1")], quickActions: [.askAboutPage])

        XCTAssertEqual(sut.chipCountForTesting, 2)
    }

    /// The input card's placeholder chip already carries the attach offer on this surface.
    func test_theActiveChatStyleDropsQuickActions() {
        sut.embed(in: parent, style: .activeChat)

        send(suggestions: [makeSuggestion(id: "s1")], quickActions: [.askAboutPage])

        XCTAssertEqual(sut.chipCountForTesting, 1)
    }

    // MARK: - Helpers

    /// The strip receives on the main queue, so an emission needs a turn of the run loop to land.
    private func send(suggestions: [ContextualSuggestedPrompt],
                      quickActions: [AIChatContextualQuickAction] = []) {
        viewState.send(makeViewState(suggestions: suggestions, quickActions: quickActions))
        let delivered = expectation(description: "emission delivered")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 1.0)
    }

    private func makeChips() -> AIChatContextualInputViewController {
        AIChatContextualInputViewController(
            voiceSearchHelper: MockVoiceSearchHelper(),
            showsBasicNativeInput: false,
            showsWelcomeMessage: false
        )
    }

    private func makeSuggestion(id: String) -> ContextualSuggestedPrompt {
        ContextualSuggestedPrompt(id: id, label: id, prompt: "Prompt \(id)", icon: nil)
    }

    private func makeViewState(suggestions: [ContextualSuggestedPrompt],
                               quickActions: [AIChatContextualQuickAction] = []) -> SheetViewState {
        SheetViewState(
            content: .webView(restoreURL: nil),
            isExpandButtonEnabled: true,
            shouldShowNewChatButton: true,
            chipState: .placeholder,
            quickActions: quickActions,
            suggestions: suggestions,
            suggestionsLoadState: .loaded,
            suggestionsAreSmart: false,
            suggestionsPageType: .none,
            suggestionsScope: .page
        )
    }

    @MainActor
    private final class AnchorStub: AIChatContextualSuggestionsStripAnchoring {
        let inputView = UIView()
        let isInputExpanded = true

        var mountedInputView: UIView? { inputView }
        var inputCardTopAnchor: NSLayoutYAxisAnchor { inputView.topAnchor }
        var inputCardLeadingAnchor: NSLayoutXAxisAnchor { inputView.leadingAnchor }
        var inputCardTrailingAnchor: NSLayoutXAxisAnchor { inputView.trailingAnchor }
    }
}
