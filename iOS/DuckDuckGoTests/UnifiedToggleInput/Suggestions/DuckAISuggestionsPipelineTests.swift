//
//  DuckAISuggestionsPipelineTests.swift
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
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAISuggestionsPipelineTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_emitsSettledSnapshot_whenURLFetchCompletesForLatestQuery() {
        let chats = CurrentValueSubject<[AIChatSuggestion], Never>([])
        let urls = CurrentValueSubject<[Suggestion], Never>([])
        let pipeline = DuckAISuggestionsPipeline(
            chatsPublisher: chats.eraseToAnyPublisher(),
            urlsPublisher: urls.eraseToAnyPublisher(),
            latestDispatchedQuery: { "swift" },
            lastCompletedURLQuery: { "swift" })

        var snapshots: [DuckAISuggestionsPipeline.Snapshot] = []
        pipeline.snapshotPublisher
            .sink { snapshots.append($0) }
            .store(in: &cancellables)

        urls.send([.website(url: URL(string: "https://swift.org")!)])

        XCTAssertEqual(snapshots.last?.isPending, false)
        XCTAssertEqual(snapshots.last?.urls.count, 1)
    }

    func test_isPending_whenLatestQueryNotYetCompleted() {
        let chats = CurrentValueSubject<[AIChatSuggestion], Never>([])
        let urls = CurrentValueSubject<[Suggestion], Never>([])
        var completed = ""
        let pipeline = DuckAISuggestionsPipeline(
            chatsPublisher: chats.eraseToAnyPublisher(),
            urlsPublisher: urls.eraseToAnyPublisher(),
            latestDispatchedQuery: { "swiftui" },
            lastCompletedURLQuery: { completed })

        var snapshots: [DuckAISuggestionsPipeline.Snapshot] = []
        pipeline.snapshotPublisher
            .sink { snapshots.append($0) }
            .store(in: &cancellables)

        chats.send([AIChatSuggestion(id: "1", title: "Hi", isPinned: false, chatId: "c")])

        XCTAssertEqual(snapshots.last?.isPending, true)

        completed = "swiftui"
        urls.send([.website(url: URL(string: "https://swiftui.org")!)])
        XCTAssertEqual(snapshots.last?.isPending, false)
    }
}
