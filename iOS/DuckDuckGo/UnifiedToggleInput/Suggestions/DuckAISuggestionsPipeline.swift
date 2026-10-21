//
//  DuckAISuggestionsPipeline.swift
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

/// Merges the recents and URL fetchers into one snapshot tagged with an explicit
/// `isPending` state, replacing the timing-based coalesce + `hasSettled` heuristic.
@MainActor
final class DuckAISuggestionsPipeline {

    struct Snapshot: Equatable {
        let chats: [AIChatSuggestion]
        let urls: [Suggestion]
        /// True while the URL loader has not yet completed the latest dispatched query.
        let isPending: Bool
    }

    let snapshotPublisher: AnyPublisher<Snapshot, Never>

    init(chatsPublisher: AnyPublisher<[AIChatSuggestion], Never>,
         urlsPublisher: AnyPublisher<[Suggestion], Never>,
         latestDispatchedQuery: @escaping () -> String,
         lastCompletedURLQuery: @escaping () -> String) {

        snapshotPublisher = Publishers.CombineLatest(
            chatsPublisher.prepend([]),
            urlsPublisher.prepend([])
        )
        .map { chats, urls in
            let pending = latestDispatchedQuery() != lastCompletedURLQuery()
            return Snapshot(chats: chats, urls: urls, isPending: pending)
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
