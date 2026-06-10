//
//  RemoteMessageModelTypeImageUrlsTests.swift
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

import Testing
import Foundation
@testable import RemoteMessaging

@Suite("RemoteMessageModelType - allImageUrls")
struct RemoteMessageModelTypeImageUrlsTests {

    @Test("Returns header URL and per-item URLs in document order for cardsList", .timeLimit(.minutes(1)))
    func cardsListReturnsHeaderAndItemUrls() {
        let headerUrl = URL(string: "https://example.com/header.png")!
        let item1Url = URL(string: "https://example.com/item1.png")!
        let item2Url = URL(string: "https://example.com/item2.png")!

        let content: RemoteMessageModelType = .cardsList(
            titleText: "Title",
            placeholder: nil,
            imageUrl: headerUrl,
            items: [
                .init(id: "item1", type: .twoLinesItem(titleText: "t", descriptionText: "d", placeholderImage: .announce, imageUrl: item1Url, action: nil), matchingRules: [], exclusionRules: []),
                .init(id: "item2", type: .featuredTwoLinesSingleActionItem(titleText: "t", descriptionText: "d", placeholderImage: .announce, imageUrl: item2Url, primaryActionText: nil, primaryAction: nil), matchingRules: [], exclusionRules: [])
            ],
            primaryActionText: "Done",
            primaryAction: .dismiss
        )

        #expect(content.allImageUrls == [headerUrl, item1Url, item2Url])
    }

    @Test("Skips items without an imageUrl", .timeLimit(.minutes(1)))
    func cardsListSkipsItemsWithoutImageUrl() {
        let headerUrl = URL(string: "https://example.com/header.png")!
        let itemUrl = URL(string: "https://example.com/item.png")!

        let content: RemoteMessageModelType = .cardsList(
            titleText: "Title",
            placeholder: nil,
            imageUrl: headerUrl,
            items: [
                .init(id: "noImage", type: .twoLinesItem(titleText: "t", descriptionText: "d", placeholderImage: .announce, imageUrl: nil, action: nil), matchingRules: [], exclusionRules: []),
                .init(id: "withImage", type: .twoLinesItem(titleText: "t", descriptionText: "d", placeholderImage: .announce, imageUrl: itemUrl, action: nil), matchingRules: [], exclusionRules: []),
                .init(id: "section", type: .titledSection(titleText: "Section", itemIDs: ["withImage"]), matchingRules: [], exclusionRules: [])
            ],
            primaryActionText: "Done",
            primaryAction: .dismiss
        )

        #expect(content.allImageUrls == [headerUrl, itemUrl])
    }

    @Test("Returns empty when cardsList has no URLs at all", .timeLimit(.minutes(1)))
    func cardsListEmptyWhenNoUrls() {
        let content: RemoteMessageModelType = .cardsList(
            titleText: "Title",
            placeholder: nil,
            imageUrl: nil,
            items: [
                .init(id: "i", type: .twoLinesItem(titleText: "t", descriptionText: "d", placeholderImage: .announce, imageUrl: nil, action: nil), matchingRules: [], exclusionRules: [])
            ],
            primaryActionText: "Done",
            primaryAction: .dismiss
        )

        #expect(content.allImageUrls.isEmpty)
    }

    @Test("Returns just the header URL for non-cardsList types", .timeLimit(.minutes(1)))
    func nonCardsListReturnsJustHeaderUrl() {
        let url = URL(string: "https://example.com/header.png")!
        let medium: RemoteMessageModelType = .medium(titleText: "t", descriptionText: "d", placeholder: .announce, imageUrl: url)

        #expect(medium.allImageUrls == [url])
    }

    @Test("Returns empty for non-cardsList types without a header URL", .timeLimit(.minutes(1)))
    func nonCardsListEmptyWhenHeaderNil() {
        let small: RemoteMessageModelType = .small(titleText: "t", descriptionText: "d")

        #expect(small.allImageUrls.isEmpty)
    }
}
