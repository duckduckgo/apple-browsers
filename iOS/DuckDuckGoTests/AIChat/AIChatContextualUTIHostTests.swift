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
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatContextualUTIHostTests: XCTestCase {

    private var originatingURL: CurrentValueSubject<URL?, Never>!
    private var didFinishURL: PassthroughSubject<URL?, Never>!
    private var pageContextHandler: MockPageContextHandler!
    private var autoAttachEnabled = false
    private var sut: AIChatContextualUTIHost!

    override func setUp() async throws {
        try await super.setUp()
        originatingURL = .init(nil)
        didFinishURL = .init()
        pageContextHandler = MockPageContextHandler()
        autoAttachEnabled = false
    }

    override func tearDown() async throws {
        sut = nil
        pageContextHandler = nil
        didFinishURL = nil
        originatingURL = nil
        try await super.tearDown()
    }

    private func makeSUT(initialAttachedContext: AIChatPageContext? = nil) {
        sut = AIChatContextualUTIHost(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            didFinishURLPublisher: didFinishURL.eraseToAnyPublisher(),
            initialAttachedContext: initialAttachedContext,
            isAutoAttachEnabled: { [weak self] in self?.autoAttachEnabled ?? false },
            pageContextHandler: pageContextHandler,
            isFireTab: false
        )
    }

    // MARK: - Chip-driven attach flow

    func test_chipAttachAction_triggersContextCollection() {
        makeSUT()
        originatingURL.send(URL(string: "https://example.com/a"))

        sut.chipViewModel.tapToAttach()

        XCTAssertEqual(pageContextHandler.triggerContextCollectionCallCount, 1)
    }

    func test_chipAttach_thenContextEmits_flipsChipToAttached() {
        let url = URL(string: "https://example.com/a")!
        makeSUT()
        originatingURL.send(url)
        sut.chipViewModel.tapToAttach()

        pageContextHandler.sendContext(makeContext(title: "Page A", url: url.absoluteString))

        guard case .attached(let title, _) = sut.chipViewModel.state else {
            return XCTFail("Expected .attached, got \(sut.chipViewModel.state)")
        }
        XCTAssertEqual(title, "Page A")
    }

    func test_chipAttach_collectionReturnsFalse_chipStaysPlaceholder() {
        pageContextHandler.triggerContextCollectionReturnValue = false
        let url = URL(string: "https://example.com/a")!
        makeSUT()
        originatingURL.send(url)

        sut.chipViewModel.tapToAttach()

        XCTAssertEqualState(sut.chipViewModel.state, .placeholder)
    }

    // MARK: - Chip-driven remove flow

    func test_chipRemoveAction_clearsAttachedContext() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: url.absoluteString))

        sut.chipViewModel.tapToRemove()

        XCTAssertEqual(pageContextHandler.clearAttachedContextCallCount, 1)
        XCTAssertEqualState(sut.chipViewModel.state, .placeholder)
    }

    func test_chipRemove_whileCollectionPending_lateResultDoesNotOverwriteClear() {
        // Regression: user taps attach (kicks off async collection) then quickly taps X. The
        // pending collection result must NOT land after the clear and re-attach the chip.
        let url = URL(string: "https://example.com/a")!
        makeSUT()
        originatingURL.send(url)

        sut.chipViewModel.tapToAttach()
        sut.chipViewModel.tapToRemove()

        // Late collection result arrives after the user already detached.
        pageContextHandler.sendContext(makeContext(title: "Page A", url: url.absoluteString))

        XCTAssertEqualState(sut.chipViewModel.state, .placeholder)
        XCTAssertNil(sut.chipViewModel.attachedContext)
    }

    func test_autoAttachOff_navigationAway_clearsAttachedContextOnHandler() {
        // Regression: when the chip clears its attachment due to nav-away (auto-attach OFF),
        // the host must also call clearAttachedContext on the handler — otherwise the FE-side
        // cached page context would survive and the next prompt would ship stale context.
        autoAttachEnabled = false
        let urlA = URL(string: "https://example.com/a")!
        originatingURL.send(urlA)
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: urlA.absoluteString))

        originatingURL.send(URL(string: "https://example.com/b"))

        XCTAssertEqual(pageContextHandler.clearAttachedContextCallCount, 1)
        XCTAssertEqualState(sut.chipViewModel.state, .placeholder)
    }

    // MARK: - Auto-attach on page-load (didFinish)

    func test_autoAttachOff_pageLoadDoesNotTriggerCollection() {
        autoAttachEnabled = false
        makeSUT()

        didFinishURL.send(URL(string: "https://example.com/b"))

        XCTAssertEqual(pageContextHandler.triggerContextCollectionCallCount, 0)
    }

    func test_autoAttachOn_pageLoadTriggersCollection() {
        autoAttachEnabled = true
        makeSUT()

        didFinishURL.send(URL(string: "https://example.com/b"))

        XCTAssertEqual(pageContextHandler.triggerContextCollectionCallCount, 1)
    }

    func test_autoAttachOn_duplicatePageLoadDeduped() {
        autoAttachEnabled = true
        makeSUT()

        let same = URL(string: "https://example.com/b")
        didFinishURL.send(same)
        didFinishURL.send(same)

        XCTAssertEqual(pageContextHandler.triggerContextCollectionCallCount, 1)
    }

    func test_autoAttachOn_didCommitURLChangeAlone_doesNotTrigger() {
        // Regression: triggers must NOT come from urlPublisher (didCommit) — too early, JS
        // returns stale content from the previous page. Only didFinish should trigger.
        autoAttachEnabled = true
        makeSUT()

        originatingURL.send(URL(string: "https://example.com/b"))

        XCTAssertEqual(pageContextHandler.triggerContextCollectionCallCount, 0)
    }

    func test_autoAttachOn_pageLoadThenContextEmits_flipsChipToAttached() {
        autoAttachEnabled = true
        let urlA = URL(string: "https://example.com/a")!
        let urlB = URL(string: "https://example.com/b")!
        makeSUT(initialAttachedContext: makeContext(title: "Page A", url: urlA.absoluteString))
        originatingURL.send(urlA)
        originatingURL.send(urlB)

        didFinishURL.send(urlB)
        pageContextHandler.sendContext(makeContext(title: "Page B", url: urlB.absoluteString))

        guard case .attached(let title, _) = sut.chipViewModel.state else {
            return XCTFail("Expected .attached on Page B, got \(sut.chipViewModel.state)")
        }
        XCTAssertEqual(title, "Page B")
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

    // MARK: - Mocks

    private final class MockPageContextHandler: AIChatPageContextHandling {
        var triggerContextCollectionCallCount = 0
        var triggerContextCollectionReturnValue = true
        var clearCallCount = 0
        var clearAttachedContextCallCount = 0
        var resubscribeCallCount = 0

        private let contextSubject = CurrentValueSubject<AIChatPageContext?, Never>(nil)
        var contextPublisher: AnyPublisher<AIChatPageContext?, Never> {
            contextSubject.eraseToAnyPublisher()
        }

        func sendContext(_ context: AIChatPageContext?) {
            contextSubject.send(context)
        }

        func triggerContextCollection() -> Bool {
            triggerContextCollectionCallCount += 1
            return triggerContextCollectionReturnValue
        }

        func clear() {
            clearCallCount += 1
            contextSubject.send(nil)
        }

        func resubscribe() {
            resubscribeCallCount += 1
        }

        func clearAttachedContext() {
            clearAttachedContextCallCount += 1
            contextSubject.send(nil)
        }
    }
}
