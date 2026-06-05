//
//  DuckAISuggestionsPipeline.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
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
