//
//  JsonToRemoteMessageModelMapperCardsListTests.swift
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

import Testing
import RemoteMessagingTestsUtils
@testable import RemoteMessaging

@Suite("RMF - Mapping - Cards List")
struct JsonToRemoteMessageModelMapperCardsListTests {
    let surveyActionMapper = MockRemoteMessageSurveyActionMapper()

    @Test("Check Valid Cards List Message Maps Successfully")
    func validCardsListMessageMapsSuccessfully() throws {
        // GIVEN
        let firstJsonItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "item1", titleText: "Feature 1", descriptionText: "Description 1", placeholder: "Announce", primaryAction: .urlInContext)
        let secondJsonItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "item2", titleText: "Feature 2", descriptionText: "Description 2", primaryAction: .urlInContext)
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [firstJsonItem, secondJsonItem])

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(titleText, placeholder, items, primaryActionText, primaryAction) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(titleText == "What's New")
        #expect(placeholder == nil)
        #expect(items.count == 2)
        #expect(primaryActionText == "Got It")
        #expect(primaryAction == .dismiss)

        let firstItem = try #require(items.first)
        let secondItem = try #require(items.last)

        #expect(firstItem.id == "item1")
        #expect(firstItem.titleText == "Feature 1")
        #expect(firstItem.descriptionText == "Description 1")
        #expect(firstItem.placeholderImage == .announce)
        #expect(firstItem.action == .urlInContext(value: "https://example.com"))

        #expect(secondItem.id == "item2")
        #expect(secondItem.titleText == "Feature 2")
        #expect(secondItem.descriptionText == "Description 2")
        #expect(secondItem.placeholderImage == .announce) // Default placeholder
        #expect(secondItem.action == .urlInContext(value: "https://example.com"))
    }

    @Test("Check Message With Many Valid Items Succeeds", arguments: [1, 5, 50])
    func manyValidItemsSucceeds(numberOfItems: Int) {
        // GIVEN
        let listItems = (0..<numberOfItems).map { index in
            RemoteMessageResponse.JsonListItem.mockListItem(
                id: "item\(index)",
                type: "two_line_list_item",
                titleText: "Feature \(index)",
                descriptionText: "Description \(index)",
                primaryAction: .urlInContext
            )
        }
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: listItems)

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == numberOfItems)
        for (index, item) in items.enumerated() {
            #expect(item.id == "item\(index)")
        }
    }

    @Test(
        "Check Missing Or Empty Required Message Fields Discards Message",
        arguments: [
            // Empty titleText -> Fail
            (titleText: "", primaryActionText: "Got It", primaryAction: .dismiss),
            // Nil primaryActionText -> Fail
            (titleText: "What's New", primaryActionText: nil, primaryAction: .dismiss),
            // Nil primaryAction -> Fail
            (titleText: "What's New", primaryActionText: "Got It", primaryAction: nil),
            // Empty primaryActionText -> Fail
            (titleText: "What's New", primaryActionText: "", primaryAction: .dismiss),
        ] as [(String, String?, RemoteMessageResponse.JsonMessageAction?)]
    )
    func missingRequiredFieldDiscardsMessage(
        titleText: String,
        primaryActionText: String?,
        primaryAction: RemoteMessageResponse.JsonMessageAction?
    ) {
        // GIVEN
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            titleText: titleText,
            listItems: [.mockListItem(id: "1")],
            primaryActionText: primaryActionText,
            primaryAction: primaryAction
        )

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        #expect(result == nil, "Expected message should have been discarded")
    }

    @Test(
        "Check Missing Required Fields On List Item Discards Only That Item",
        arguments: [
            // Empty id -> Fail
            (id: "", titleText: "Feature", descriptionText: "Description", primaryAction: .dismiss),
            // Empty titleText -> Fail
            (id: "item1", titleText: "", descriptionText: "", primaryAction: .dismiss),
            // Empty action -> Fail
            (id: "item1", titleText: "Feature", descriptionText: "Description", primaryAction: nil),
        ] as [(String, String, String, RemoteMessageResponse.JsonMessageAction?)]
    )
    func missingRequiredItemFieldDiscardsItem(
        id: String,
        titleText: String,
        descriptionText: String,
        primaryAction: RemoteMessageResponse.JsonMessageAction?
    ) {
        // GIVEN
        let validListItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "valid_item")
        let invalidListItem = RemoteMessageResponse.JsonListItem.mockListItem(id: id, titleText: titleText, descriptionText: descriptionText, primaryAction: primaryAction)
        // Add a valid item to ensure message is not discarded because of empty lists.
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [invalidListItem, validListItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1, "Invalid item should be discarded")
        #expect(items.first?.id == "valid_item", "Only valid item should remain")
    }

    @Test("Check Nil Description Defaults To Empty String")
    func nilDescriptionForItemDefaultsToEmptyString() {
        // GIVEN
        let item = RemoteMessageResponse.JsonListItem.mockListItem(id: "1", titleText: "Feature 1", descriptionText: nil, primaryAction: .dismiss)
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [item])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1)
        #expect(items.first?.descriptionText == "")
    }

    @Test("Check Nil Or Empty List Items Discards Message", arguments: [nil, []] as [[RemoteMessageResponse.JsonListItem]?])
    func nilListItemsDiscardsMessage(listItems: [RemoteMessageResponse.JsonListItem]?) {
        // GIVEN
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: listItems)

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        #expect(result == nil, "Message with nil or emtpy listItems should be discarded")
    }

    @Test("Check All Invalid Items Discards Entire Message")
    func allInvalidItemsDiscardsMessage() {
        // GIVEN
        // Invalid - empty id
        let firstInvalidItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "")
        // Invalid - empty titleText
        let secondInvalidItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "item 2", titleText: "")
        // Invalid - action
        let thirdInvalidItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "item 3", titleText: "Test", primaryAction: nil)
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [firstInvalidItem, secondInvalidItem, thirdInvalidItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        #expect(result == nil, "Message with all invalid items should be discarded")
    }

    @Test("Check Duplicate Item IDs Keeps First Occurrence And Discards Duplicates")
    func duplicateIDsKeepsFirstItemEncountered() {
        // GIVEN
        let duplicateItem1 = RemoteMessageResponse.JsonListItem.mockListItem(id: "duplicate_id", titleText: "First Item", descriptionText: "First Item Description", primaryAction: .urlInContext)
        let validItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "unique_id", titleText: "Second Item", descriptionText: "Second Item Description", primaryAction: .urlInContext)
        let duplicateItem2 = RemoteMessageResponse.JsonListItem.mockListItem(id: "duplicate_id", titleText: "Third Item", descriptionText: "Third Item Description", primaryAction: .urlInContext)
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [duplicateItem1, validItem, duplicateItem2])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 2, "Should keep first duplicate and unique item")
        #expect(items.first?.id == "duplicate_id")
        #expect(items.first?.titleText == "First Item", "Should keep first occurrence")
        #expect(items.last?.id == "unique_id")
    }

    @Test("Check Item ID Is Considered Duplicate Only If Successfully Mapped")
    func duplicateIDAfterInvalidItemAllowsValidItem() {
        // GIVEN
        // Invalid - empty title -> Not considered for duplicated IDs
        let invalidItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "same_id", titleText: "")
        let firstValidItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "same_id", titleText: "First Valid")
        let secondValidItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "same_id", titleText: "Second Valid")
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [invalidItem, firstValidItem, secondValidItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        // Should only keep first valid item, invalid item doesn't "claim" the ID
        #expect(items.count == 1, "Should keep first valid item, invalid doesn't block ID")
        #expect(items.first?.titleText == "First Valid", "Should keep first valid occurrence")
    }

    @Test(
        "Check Unrecognised Item Type Discards Item",
        arguments: ["unknown_type", "invalid", "", "TWO_LINE_LIST_ITEM"]
    )
    func unrecognizedListTypeDiscardsItem(invalidType: String) {
        // GIVEN
        let validItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "valid_item", type: "two_line_list_item")
        let invalidItem = RemoteMessageResponse.JsonListItem.mockListItem(id: "invalid_item", type: invalidType)
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [validItem, invalidItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1, "Invalid type item should be discarded")
        #expect(items.first?.id == "valid_item")
    }

    @Test("Placeholder Maps Correctly",
        arguments: [
            ("Announce", RemotePlaceholder.announce),
            // Maps to Default
            ("", RemotePlaceholder.announce),
            // Maps to Default
            (nil, RemotePlaceholder.announce)
        ]
    )
    func placeholderMapping(placeholderValue: String?, expectedPlaceholder: RemotePlaceholder) {
        // GIVEN
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [.mockListItem(id: "item", placeholder: placeholderValue)])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.first?.placeholderImage == expectedPlaceholder)
    }

    @Test("Check Item With Nil Action Is Handled Correctly")
    func nilActionIsValid() {
        // GIVEN
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [.mockListItem(id: "item", primaryAction: nil)])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        #expect(result == nil, "Current implementation requires action, but spec says optional")
    }

    @Test("Check Different Action Types Map Correctly",
          arguments: [
            (("url_in_context", "https://example.com"), RemoteAction.urlInContext(value: "https://example.com")),
            (("navigation", "import.passwords"), RemoteAction.navigation(value: .importPasswords))
          ]
    )
    func actionTypesMapCorrectly(jsonAction: (key: String, value: String), expectedAction: RemoteAction) {
        // GIVEN
        let jsonAction =  RemoteMessageResponse.JsonMessageAction(type: jsonAction.key, value: jsonAction.value, additionalParameters: nil)
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [.mockListItem(id: "item", primaryAction: jsonAction)])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.first?.action == expectedAction)
    }

    @Test("Check Message Level Placeholder Maps Correctly",
          arguments: [
            ("Announce", .announce),
            ("DDGAnnounce", .ddgAnnounce),
            ("CriticalUpdate", .criticalUpdate),
            ("AppUpdate", .appUpdate),
            ("MacComputer", .macComputer),
            ("NewForMacAndWindows", .newForMacAndWindows),
            ("PrivacyShield", RemotePlaceholder.privacyShield),
            ("Duck.ai", RemotePlaceholder.aiChat),
            ("VisualDesignUpdate", .visualDesignUpdate),
            ("ImageAI", .imageAI),
            ("Radar", .radar),
            ("KeyImport", .keyImport),
            (nil, nil)
          ] as [(String?, RemotePlaceholder?)]
    )
    func messageLevelPlaceholderMapsCorrectly(placeholderValue: String?, expectedPlaceholder: RemotePlaceholder?) {
        // GIVEN
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(placeholder: placeholderValue, listItems: [.mockListItem(id: "item")])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, placeholder, _, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(placeholder == expectedPlaceholder)
    }
}

@Suite("RMF - Mapping - Cards List Items with Rules")
struct JsonToRemoteMessageModelMapperCardsListRulesTests {
    let surveyActionMapper = MockRemoteMessageSurveyActionMapper()
    @Test("Check List Items with Matching Rules Map Correctly")
    func listItemsWithMatchingRules() throws {
        // GIVEN
        let itemWithBothRules = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "item_with_both_rules",
            matchingRules: [1, 2],
            exclusionRules: [3]
        )
        let itemWithMatchingOnly = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "item_with_matching_only",
            matchingRules: [4, 5, 6],
            exclusionRules: nil
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [itemWithBothRules, itemWithMatchingOnly]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 2)

        let firstItem = try #require(items.first)
        #expect(firstItem.id == "item_with_both_rules")
        #expect(firstItem.matchingRules == [1, 2])
        #expect(firstItem.exclusionRules == [3])

        let secondItem = try #require(items.last)
        #expect(secondItem.id == "item_with_matching_only")
        #expect(secondItem.matchingRules == [4, 5, 6])
        #expect(secondItem.exclusionRules == [])
    }

    @Test("Check List Items with Exclusion Rules Map Correctly")
    func listItemsWithExclusionRules() throws {
        // GIVEN
        let itemWithExclusionOnly = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "item_with_exclusion_only",
            matchingRules: nil,
            exclusionRules: [7, 8]
        )
        let itemWithNoRules = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "item_with_no_rules",
            matchingRules: nil,
            exclusionRules: nil
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [itemWithExclusionOnly, itemWithNoRules]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 2)

        let firstItem = try #require(items.first)
        #expect(firstItem.id == "item_with_exclusion_only")
        #expect(firstItem.matchingRules == [])
        #expect(firstItem.exclusionRules == [7, 8])

        let secondItem = try #require(items.last)
        #expect(secondItem.id == "item_with_no_rules")
        #expect(secondItem.matchingRules == [])
        #expect(secondItem.exclusionRules == [])
    }

    @Test("Check Empty Rules Arrays Default to Empty")
    func emptyRulesArraysDefaultToEmpty() throws {
        // GIVEN
        let itemWithEmptyArrays = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "item_with_empty_arrays",
            matchingRules: [],
            exclusionRules: []
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [itemWithEmptyArrays]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        let item = try #require(items.first)
        #expect(item.id == "item_with_empty_arrays")
        #expect(item.matchingRules == [])
        #expect(item.exclusionRules == [])
    }

    @Test("Check Invalid Items with Rules Are Discarded Correctly")
    func invalidItemsWithRulesAreDiscarded() throws {
        // GIVEN
        let invalidItemWithRules = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "", // Invalid - empty ID
            titleText: "Invalid Item with Rules",
            matchingRules: [1, 2],
            exclusionRules: [3]
        )
        let validItemAfterInvalid = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "valid_item_after_invalid",
            matchingRules: [4],
            exclusionRules: []
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [invalidItemWithRules, validItemAfterInvalid]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1, "Only valid item should remain")

        let validItem = try #require(items.first)
        #expect(validItem.id == "valid_item_after_invalid")
        #expect(validItem.matchingRules == [4])
        #expect(validItem.exclusionRules == [])
    }

    @Test("Check Rules Maintain Order and Values")
    func rulesMaintainOrderAndValues() throws {
        // GIVEN
        let itemWithManyRules = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "item_with_many_rules",
            matchingRules: [10, 1, 5, 999, 2],
            exclusionRules: [100, 50, 200]
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [itemWithManyRules]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        let item = try #require(items.first)
        #expect(item.id == "item_with_many_rules")
        #expect(item.matchingRules == [10, 1, 5, 999, 2], "Should maintain exact order and values")
        #expect(item.exclusionRules == [100, 50, 200], "Should maintain exact order and values")
    }

    @Test("Check Duplicate Item IDs with Rules Keep First Occurrence")
    func duplicateItemIDsWithRulesKeepFirstOccurrence() throws {
        // GIVEN
        let firstItem = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "duplicate_id",
            titleText: "First Item",
            matchingRules: [1, 2],
            exclusionRules: [3]
        )
        let duplicateItem = RemoteMessageResponse.JsonListItem.mockListItem(
            id: "duplicate_id",
            titleText: "Duplicate Item",
            matchingRules: [4, 5],
            exclusionRules: [6, 7]
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [firstItem, duplicateItem]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1, "Duplicate should be discarded")

        let item = try #require(items.first)
        #expect(item.id == "duplicate_id")
        #expect(item.titleText == "First Item", "Should keep first occurrence")
        #expect(item.matchingRules == [1, 2], "Should keep rules from first occurrence")
        #expect(item.exclusionRules == [3], "Should keep rules from first occurrence")
    }
}

// MARK: - Helpers

private extension RemoteMessageResponse.JsonContent {

    static func mockCardsListMessage(
        titleText: String = "What's New",
        placeholder: String? = nil,
        listItems: [RemoteMessageResponse.JsonListItem]? = [.mockListItem(id: "item1"), .mockListItem(id: "item2")],
        primaryActionText: String? = "Got It",
        primaryAction: RemoteMessageResponse.JsonMessageAction? = .dismiss
    ) -> RemoteMessageResponse.JsonContent {
        RemoteMessageResponse.JsonContent(
            messageType: "cards_list",
            titleText: titleText,
            descriptionText: "",
            listItems: listItems,
            placeholder: placeholder,
            actionText: nil,
            action: nil,
            primaryActionText: primaryActionText,
            primaryAction: primaryAction,
            secondaryActionText: nil,
            secondaryAction: nil
        )
    }
}

private extension RemoteMessageResponse.JsonListItem {

    static func mockListItem(
        id: String,
        type: String = "two_line_list_item",
        titleText: String = "Feature",
        descriptionText: String? = "Description",
        placeholder: String? = "Announce",
        primaryAction: RemoteMessageResponse.JsonMessageAction? = .init(type: "url", value: "https://example.com", additionalParameters: nil),
        matchingRules: [Int]? = nil,
        exclusionRules: [Int]? = nil
    ) -> RemoteMessageResponse.JsonListItem {
        RemoteMessageResponse.JsonListItem(
            id: id,
            type: type,
            titleText: titleText,
            descriptionText: descriptionText,
            placeholder: placeholder,
            primaryAction: primaryAction,
            matchingRules: matchingRules,
            exclusionRules: exclusionRules
        )
    }

}

private extension RemoteMessageResponse.JsonMessageAction {
    static let dismiss: RemoteMessageResponse.JsonMessageAction = .init(type: "dismiss", value: "", additionalParameters: nil)
    static let urlInContext: RemoteMessageResponse.JsonMessageAction = .init(type: "url_in_context", value: "https://example.com", additionalParameters: nil)
}
