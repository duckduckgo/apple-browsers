//
//  DuckAISuggestionsSelectionTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAISuggestionsSelectionTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    private func makeSource(chats: [AIChatSuggestion], urls: [Suggestion], query: String)
        -> DuckAISuggestionsSource {
        let subject = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: chats, urls: urls, isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: subject.eraseToAnyPublisher(),
                                             query: { query })
        // Drain one emission so the source captures the snapshot.
        source.sectionsPublisher.sink { _ in }.store(in: &cancellables)
        return source
    }

    func test_resolvesChatRowToChatSelection() {
        let chat = AIChatSuggestion(id: "abc", title: "Hi", isPinned: false, chatId: "c1")
        let source = makeSource(chats: [chat], urls: [], query: "")
        XCTAssertEqual(source.selection(forRowID: "chat-abc"), .chat(chat))
    }

    func test_resolvesURLRowToURLSelection() {
        let url = URL(string: "https://swift.org")!
        let suggestion = Suggestion.website(url: url)
        let source = makeSource(chats: [], urls: [suggestion], query: "sw")
        XCTAssertEqual(source.selection(forRowID: "urls-website-\(url.absoluteString)"), .url(suggestion))
    }

    func test_resolvesSearchRowToSearchSelection() {
        let source = makeSource(chats: [], urls: [], query: "weather")
        XCTAssertEqual(source.selection(forRowID: "search-searchDuckDuckGo"), .searchDuckDuckGo("weather"))
    }

    func test_unknownRowIDResolvesToNil() {
        let source = makeSource(chats: [], urls: [], query: "")
        XCTAssertNil(source.selection(forRowID: "does-not-exist"))
    }
}
