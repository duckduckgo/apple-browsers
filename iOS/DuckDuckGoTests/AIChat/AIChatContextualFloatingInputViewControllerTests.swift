//
//  AIChatContextualFloatingInputViewControllerTests.swift
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
final class AIChatContextualFloatingInputViewControllerTests: XCTestCase {

    private final class DelegateSpy: AIChatContextualFloatingInputViewControllerDelegate {
        var dismissRequestCount = 0
        func aiChatContextualFloatingInputViewControllerDidRequestDismiss(_ viewController: AIChatContextualFloatingInputViewController) {
            dismissRequestCount += 1
        }
    }

    private var originatingURL: CurrentValueSubject<URL?, Never>!

    override func setUp() async throws {
        try await super.setUp()
        originatingURL = .init(nil)
    }

    override func tearDown() async throws {
        originatingURL = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeHost() -> AIChatContextualUTIHost {
        AIChatContextualUTIHost(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            initialAttachedContext: nil,
            initialAttachmentDeliveryState: .delivered,
            hasActiveChat: { false },
            isAutoAttachEnabled: { false },
            isFireTab: false
        )
    }

    private func makeChips() -> AIChatContextualInputViewController {
        AIChatContextualInputViewController(
            voiceSearchHelper: MockVoiceSearchHelper(),
            showsBasicNativeInput: false,
            showsWelcomeMessage: false
        )
    }

    private func makeSubject() -> (AIChatContextualFloatingInputViewController, DelegateSpy, UIViewController) {
        let subject = AIChatContextualFloatingInputViewController(utiHost: makeHost(), chipsViewController: makeChips())
        let spy = DelegateSpy()
        subject.delegate = spy

        let parent = UIViewController()
        parent.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        subject.install(in: parent)
        parent.view.layoutIfNeeded()

        return (subject, spy, parent)
    }

    // MARK: - Install

    func testInstallAddsItAsAChildOfThePresenter() {
        let (subject, _, parent) = makeSubject()

        XCTAssertTrue(parent.children.contains(subject))
        XCTAssertTrue(subject.view.isDescendant(of: parent.view))
    }

    func testInstallMountsBothTheChipsAndTheInput() {
        let (subject, _, _) = makeSubject()

        XCTAssertEqual(subject.children.count, 2)
        XCTAssertTrue(subject.children.contains(subject.chipsViewController))
    }

    func testInstallingTwiceInTheSameParentDoesNotDuplicate() {
        let (subject, _, parent) = makeSubject()

        subject.install(in: parent)

        XCTAssertEqual(parent.children.filter { $0 === subject }.count, 1)
    }

    // MARK: - Dismissal

    func testTappingThePageRequestsDismissal() {
        let (subject, spy, _) = makeSubject()

        subject.simulatePageTapForTesting()

        XCTAssertEqual(spy.dismissRequestCount, 1)
    }

    /// The tap that dismisses must still reach the page, so whatever it hit — a link, a text field —
    /// activates on the same tap rather than needing a second one.
    func testThePageTapRecognizerDoesNotConsumeTheTouch() throws {
        let (_, _, parent) = makeSubject()
        let recognizer = try XCTUnwrap(parent.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)

        XCTAssertFalse(recognizer.cancelsTouchesInView)
        XCTAssertFalse(recognizer.delaysTouchesBegan)
        XCTAssertFalse(recognizer.delaysTouchesEnded)
    }

    func testRemoveDetachesThePageTapRecognizerFromThePresenter() {
        let (subject, _, parent) = makeSubject()
        XCTAssertFalse(parent.view.gestureRecognizers?.isEmpty ?? true)

        subject.remove()

        XCTAssertTrue(parent.view.gestureRecognizers?.isEmpty ?? true)
    }

    /// The page stays scrollable underneath, so the surface must only claim touches on its own controls.
    func testTouchesOutsideTheControlsPassThroughToThePage() {
        let (subject, _, _) = makeSubject()
        let emptyArea = CGPoint(x: subject.view.bounds.midX, y: subject.view.bounds.minY + 1)

        XCTAssertNil(subject.view.hitTest(emptyArea, with: nil))
    }

    func testAccessibilityEscapeRequestsDismissal() {
        let (subject, spy, _) = makeSubject()

        XCTAssertTrue(subject.accessibilityPerformEscape())

        XCTAssertEqual(spy.dismissRequestCount, 1)
    }

    func testRemoveDetachesEverything() {
        let (subject, _, parent) = makeSubject()

        subject.remove()

        XCTAssertFalse(parent.children.contains(subject))
        XCTAssertNil(subject.view.superview)
        XCTAssertTrue(subject.children.isEmpty)
    }

    /// The host reuses its input view, so a dismissal must hand it back untouched.
    func testRemoveRestoresTheInputViewItBorrowed() {
        let host = makeHost()
        let subject = AIChatContextualFloatingInputViewController(utiHost: host, chipsViewController: makeChips())
        let parent = UIViewController()
        parent.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        subject.install(in: parent)
        let inputView = host.mount(in: subject)

        subject.remove()

        XCTAssertEqual(inputView.alpha, 1)
        XCTAssertEqual(inputView.transform, .identity)
    }

    // MARK: - Chips entrance

    /// An empty batch must not consume the entrance: page context attaches before suggestions
    /// resolve, so the first batches legitimately carry nothing to animate.
    func testAnEmptyBatchDoesNotConsumeTheEntrance() {
        let (subject, _, _) = makeSubject()

        subject.playChipsEntranceIfNeeded()
        XCTAssertFalse(subject.hasPlayedChipsEntranceForTesting)

        subject.chipsViewController.updateStartActions(suggestions: [], quickActions: [.summarize])
        subject.playChipsEntranceIfNeeded()
        XCTAssertTrue(subject.hasPlayedChipsEntranceForTesting)
    }

    func testEntranceIsConsumedByTheFirstBatchWithChips() {
        let (subject, _, _) = makeSubject()
        subject.chipsViewController.updateStartActions(suggestions: [], quickActions: [.summarize])

        subject.playChipsEntranceIfNeeded()
        XCTAssertTrue(subject.hasPlayedChipsEntranceForTesting)

        subject.chipsViewController.updateStartActions(suggestions: [], quickActions: [.summarize, .askAboutPage])
        subject.playChipsEntranceIfNeeded()

        XCTAssertTrue(subject.hasPlayedChipsEntranceForTesting)
        XCTAssertEqual(subject.chipsViewController.startActionCount, 2)
    }
}
