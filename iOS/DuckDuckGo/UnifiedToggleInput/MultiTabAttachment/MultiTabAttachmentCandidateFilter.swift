//
//  MultiTabAttachmentCandidateFilter.swift
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

import Foundation

enum MultiTabAttachmentCandidateFilter {
    static func filter(_ tabs: [MultiTabAttachmentCandidate], query: String) -> [MultiTabAttachmentCandidate] {
        guard !query.isEmpty else { return tabs }
        let normalizedQuery = query.lowercased()

        struct ScoredItem {
            let item: MultiTabAttachmentCandidate
            let score: Int
            let inputIndex: Int
        }

        let scoredItems: [ScoredItem] = tabs.enumerated().compactMap { index, item in
            var score = 0
            if item.title.lowercased().contains(normalizedQuery) {
                score += 2
            }
            if item.url.absoluteString.lowercased().contains(normalizedQuery) {
                score += 1
            }
            guard score > 0 else { return nil }
            return ScoredItem(item: item, score: score, inputIndex: index)
        }

        var result = scoredItems
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.inputIndex < rhs.inputIndex
            }
            .map(\.item)
        if let currentIndex = result.firstIndex(where: \.isCurrentTab), currentIndex != 0 {
            let current = result.remove(at: currentIndex)
            result.insert(current, at: 0)
        }
        return result
    }
}
