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

        guard case let .cardsList(titleText, placeholder, items, primaryActionText, primaryAction) = firstMessage.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        // THEN
        #expect(titleText == "What's New")
        #expect(placeholder == nil)
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
        guard case let .cardsList(_, _, items, _, _) = message.content else {
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

        guard case let .cardsList(_, _, items, _, _) = message.content else {
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
        guard case let .cardsList(_, _, items, _, _) = message.content else {
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

@Suite("RMF - Mapping - Cards List Items with Rules - JSON Integration")
struct JsonToRemoteMessageModelMapperCardsListRulesIntegrationTests {
    let config: RemoteConfigModel

    init() throws {
        self.config = try RemoteMessagingConfigDecoder.decodeAndMapJson(
            fileName: "remote-messaging-config-cards-list-items-with-rules.json",
            bundle: .module
        )
    }

    @Test("Check List Items with Matching and Exclusion Rules Map Correctly")
    func listItemsWithMatchingAndExclusionRulesMapped() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_with_item_rules" }))

        guard case let .cardsList(_, _, items, _, _) = message.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        // THEN
        #expect(items.count == 5)

        // Item with both matching and exclusion rules
        let itemWithBothRules = try #require(items.first(where: { $0.id == "item_with_both_rules" }))
        #expect(itemWithBothRules.matchingRules == [1, 2])
        #expect(itemWithBothRules.exclusionRules == [3])

        // Item with matching rules only
        let itemWithMatchingOnly = try #require(items.first(where: { $0.id == "item_with_matching_only" }))
        #expect(itemWithMatchingOnly.matchingRules == [4, 5, 6])
        #expect(itemWithMatchingOnly.exclusionRules == [])

        // Item with exclusion rules only
        let itemWithExclusionOnly = try #require(items.first(where: { $0.id == "item_with_exclusion_only" }))
        #expect(itemWithExclusionOnly.matchingRules == [])
        #expect(itemWithExclusionOnly.exclusionRules == [7, 8])

        // Item with no rules
        let itemWithNoRules = try #require(items.first(where: { $0.id == "item_with_no_rules" }))
        #expect(itemWithNoRules.matchingRules == [])
        #expect(itemWithNoRules.exclusionRules == [])

        // Item with empty arrays
        let itemWithEmptyArrays = try #require(items.first(where: { $0.id == "item_with_empty_arrays" }))
        #expect(itemWithEmptyArrays.matchingRules == [])
        #expect(itemWithEmptyArrays.exclusionRules == [])
    }

    @Test("Check Null Rules Default to Empty Arrays")
    func nullRulesDefaultToEmptyArrays() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_null_rules" }))

        guard case let .cardsList(_, _, items, _, _) = message.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        // THEN
        #expect(items.count == 1)

        let item = try #require(items.first)
        #expect(item.id == "item_with_null_rules")
        #expect(item.matchingRules == [])
        #expect(item.exclusionRules == [])
    }

    @Test("Check Missing Rules Fields Default to Empty Arrays")
    func missingRulesFieldsDefaultToEmptyArrays() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_missing_rules" }))

        guard case let .cardsList(_, _, items, _, _) = message.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        // THEN
        #expect(items.count == 1)

        let item = try #require(items.first)
        #expect(item.id == "item_missing_rules")
        #expect(item.matchingRules == [])
        #expect(item.exclusionRules == [])
    }

    @Test("Check Invalid Items with Rules Are Discarded Correctly")
    func invalidItemsWithRulesAreDiscarded() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_invalid_items_with_rules" }))

        guard case let .cardsList(_, _, items, _, _) = message.content else {
            Issue.record("Expected cardsList content type")
            return
        }

        // THEN
        #expect(items.count == 1, "Only valid item should remain")

        let validItem = try #require(items.first)
        #expect(validItem.id == "valid_item_after_invalid")
        #expect(validItem.matchingRules == [4])
        #expect(validItem.exclusionRules == [])
    }

    @Test("Check Message Level Rules Are Preserved")
    func messageLevelRulesArePreserved() throws {
        // WHEN
        let message = try #require(config.messages.first(where: { $0.id == "cards_list_with_item_rules" }))

        // THEN
        #expect(message.matchingRules == [1], "Message level matching rules should be preserved")
        #expect(message.exclusionRules == [], "Message level exclusion rules should be preserved")
    }

    @Test("Check Rules Configuration Contains Expected Rules")
    func rulesConfigurationContainsExpectedRules() throws {
        // THEN
        #expect(config.rules.count == 8, "Should have all rules from test configuration")

        // Verify some key rules exist
        let rule1 = try #require(config.rules.first(where: { $0.id == 1 }))
        #expect(rule1.targetPercentile?.before == 0.5, "Rule 1 should have percentile targeting")

        let rule2 = try #require(config.rules.first(where: { $0.id == 2 }))
        #expect(rule2.targetPercentile == nil, "Rule 2 should not have percentile targeting")
    }
}
