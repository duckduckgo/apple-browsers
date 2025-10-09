//
//  JsonToRemoteMessageModelMapperCardsListIntegrationTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Testing
import RemoteMessagingTestsUtils
@testable import RemoteMessaging

@Suite("RMF - Mapping - Cards List - JSON Integration")
struct JsonToRemoteMessageModelMapperCardsListIntegrationTests {
    let config: RemoteConfigModel

    init() throws {
        self.config = try RemoteMessagingConfigDecoder.decodeAndMapJson(
            fileName: "remote-messaging-config-cards-list-items.json",
            bundle: .module
        )
    }

    @Test("Check Valid Cards List Configuration Decodes And Maps Successfully")
    func validCardsListConfigurationDecodesAndMapsSuccessfully() throws {
        // GIVEN
        // Discard messages with following IDs:
        //  - "cards_list_with_duplicate_ids"
        //  - "cards_list_with_invalid_items"
        //  - "cards_list_with_all_placeholders"
        #expect(config.messages.count == 4, "Should decode all messages in config")

        // WHEN
        let firstMessage = try #require(config.messages.first(where: { $0.id == "whats_new_v1" }))

        guard case let .cardsList(titleText, items, primaryActionText, primaryAction) = firstMessage.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        // THEN
        #expect(titleText == "What's New")
        #expect(items.count == 3)
        #expect(primaryActionText == "Got It")
        #expect(primaryAction == .dismiss)

        // Verify first item
        #expect(items[safe: 0]?.id == "hide_search_images")
        #expect(items[safe: 0]?.type == .twoLinesItem)
        #expect(items[safe: 0]?.titleText == "Hide AI Images in Search")
        #expect(items[safe: 0]?.descriptionText == "Easily hide AI images from your search results")
        #expect(items[safe: 0]?.placeholderImage == .announce)
        #expect(items[safe: 0]?.action == .urlInContext(value: "https://example.com"))

        // Verify second item
        #expect(items[safe: 1]?.id == "enhanced_scam_blocker")
        #expect(items[safe: 1]?.titleText == "Enhanced Scam Blocker")
        #expect(items[safe: 1]?.placeholderImage == .privacyShield)
        #expect(items[safe: 1]?.action == .urlInContext(value: "https://example.com"))

        // Verify third item
        #expect(items[safe: 2]?.id == "duck_ai_chat")
        #expect(items[safe: 2]?.titleText == "Duck AI Chat")
        #expect(items[safe: 2]?.placeholderImage == .aiChat)
        #expect(items[safe: 2]?.action == .navigation(value: .importPasswords))
    }

    @Test("Check Duplicate Item IDs Are Handled - First Occurrence Kept")
    func duplicateItemIDsHandledCorrectly() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_with_duplicate_ids" }))

        // THEN
        guard case let .cardsList(_, items, _, _) = message.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        #expect(items.count == 1, "Duplicate ID should be discarded")
        #expect(items.first?.id == "feature_1")
        #expect(items.first?.titleText == "First Occurrence", "Should keep first occurrence")
    }

    @Test("Check Invalid Items Are Discarded But Valid Items Remain")
    func invalidItemsAreDiscardedWhileValidItemsRemain() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_with_invalid_items" }))

        guard case let .cardsList(_, items, _, _) = message.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        #expect(items.count == 1, "Invalid items should be discarded")
        #expect(items.first?.id == "valid_item", "Only valid item should remain")
        #expect(items.first?.titleText == "Valid Item")
    }

    @Test("Check Empty ListItems Array Results In Message Being Discarded")
    func emptyListItemsDiscardsMessage() throws {
        // WHEN
        let emptyItemsMessage = config.messages.first(where: { $0.id == "cards_list_empty_items" })

        // THEN
        #expect(emptyItemsMessage == nil, "Message with empty listItems should be discarded")
    }

    @Test("Check Nil ListItems Results In Message Being Discarded")
    func nilListItemsDiscardsMessage() throws {
        // WHEN
        let nilItemsMessage = config.messages.first(where: { $0.id == "cards_list_nil_items" })

        // THEN
        #expect(nilItemsMessage == nil, "Message with nil listItems should be discarded")
    }

    @Test("Check All Invalid Items Results In Message Being Discarded")
    func allInvalidItemsDiscardsMessage() throws {
        // WHEN
        let allInvalidMessage = config.messages.first(where: { $0.id == "cards_list_all_invalid_items" })

        // THEN
        #expect(allInvalidMessage == nil, "Message with all invalid items should be discarded")
    }

    @Test("Check All Placeholder Types Map Correctly")
    func checkPlaceholderTypesMapCorrectly() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_with_all_placeholders" }))

        // THEN
        guard case let .cardsList(_, items, _, _) = message.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        #expect(items.count == 3)
        #expect(items[safe: 0]?.placeholderImage == .announce, "Explicit Announce placeholder")
        #expect(items[safe: 1]?.placeholderImage == .ddgAnnounce, "DDGAnnounce placeholder")
        #expect(items[safe: 2]?.placeholderImage == .announce, "Nil placeholder should default to announce")
    }

    @Test("Check Surfaces Are Validated For Cards List Message Type")
    func checkSurfacesValidatedForCardsListType() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "whats_new_v1" }))

        // THEN
        // Cards list supports only modal and dedicatedTab surfaces
        #expect(message.surfaces == [.modal, .dedicatedTab])
        #expect(!message.surfaces.contains(.newTabPage), "newTabPage not supported for cards_list")
    }

    @Test("Check Message Content Preserves All Field Values")
    func checkMessageContentPreservesAllFieldValues() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "whats_new_v1" }))

        // THEN
        #expect(message.isMetricsEnabled == true, "Metrics should be enabled by default")
        #expect(message.matchingRules.isEmpty, "No matching rules in test config")
        #expect(message.exclusionRules.isEmpty, "No exclusion rules in test config")
    }
}
