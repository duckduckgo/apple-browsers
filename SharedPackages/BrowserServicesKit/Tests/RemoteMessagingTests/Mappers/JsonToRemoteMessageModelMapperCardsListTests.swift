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
        let firstJsonItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1", titleText: "Feature 1", descriptionText: "Description 1", placeholder: "Announce", primaryAction: .urlInContext)
        let secondJsonItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item2", titleText: "Feature 2", descriptionText: "Description 2", primaryAction: .urlInContext)
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
            RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
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
            listItems: [.mockTwoLinesListItem(id: "1")],
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
            (id: "item1", titleText: "", descriptionText: "", primaryAction: .dismiss)
        ] as [(String, String, String, RemoteMessageResponse.JsonMessageAction?)]
    )
    func missingRequiredItemFieldDiscardsItem(
        id: String,
        titleText: String,
        descriptionText: String,
        primaryAction: RemoteMessageResponse.JsonMessageAction?
    ) {
        // GIVEN
        let validListItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "valid_item")
        let invalidListItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: id, titleText: titleText, descriptionText: descriptionText, primaryAction: primaryAction)
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
        let item = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "1", titleText: "Feature 1", descriptionText: nil, primaryAction: .dismiss)
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
        let firstInvalidItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "")
        // Invalid - empty titleText
        let secondInvalidItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item 2", titleText: "")
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [firstInvalidItem, secondInvalidItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        #expect(result == nil, "Message with all invalid items should be discarded")
    }

    @Test("Check Duplicate Item IDs Keeps First Occurrence And Discards Duplicates")
    func duplicateIDsKeepsFirstItemEncountered() {
        // GIVEN
        let duplicateItem1 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "duplicate_id", titleText: "First Item", descriptionText: "First Item Description", primaryAction: .urlInContext)
        let validItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "unique_id", titleText: "Second Item", descriptionText: "Second Item Description", primaryAction: .urlInContext)
        let duplicateItem2 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "duplicate_id", titleText: "Third Item", descriptionText: "Third Item Description", primaryAction: .urlInContext)
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
        let invalidItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "same_id", titleText: "")
        let firstValidItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "same_id", titleText: "First Valid")
        let secondValidItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "same_id", titleText: "Second Valid")
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
        let validItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "valid_item", type: "two_line_list_item")
        let invalidItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "invalid_item", type: invalidType)
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
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [.mockTwoLinesListItem(id: "item", placeholder: placeholderValue)])

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
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [.mockTwoLinesListItem(id: "item", primaryAction: nil)])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        #expect(result != nil)
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
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [.mockTwoLinesListItem(id: "item", primaryAction: jsonAction)])

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
            ("PrivacyShield", RemotePlaceholder.subscription),
            ("Duck.ai", RemotePlaceholder.aiChat),
            ("VisualDesignUpdate", .visualDesignUpdate),
            ("ImageAI", .imageAI),
            ("Radar", .radar),
            ("RadarCheckGreen", .radarCheckGreen),
            ("RadarCheckPurple", .radarCheckPurple),
            ("KeyImport", .keyImport),
            ("PIR", .pir),
            ("Subscription", .subscription),
            (nil, nil)
          ] as [(String?, RemotePlaceholder?)]
    )
    func messageLevelPlaceholderMapsCorrectly(placeholderValue: String?, expectedPlaceholder: RemotePlaceholder?) {
        // GIVEN
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(placeholder: placeholderValue, listItems: [.mockTwoLinesListItem(id: "item")])

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
        let itemWithBothRules = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
            id: "item_with_both_rules",
            matchingRules: [1, 2],
            exclusionRules: [3]
        )
        let itemWithMatchingOnly = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
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
        let itemWithExclusionOnly = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
            id: "item_with_exclusion_only",
            matchingRules: nil,
            exclusionRules: [7, 8]
        )
        let itemWithNoRules = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
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
        let itemWithEmptyArrays = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
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
        let invalidItemWithRules = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
            id: "", // Invalid - empty ID
            titleText: "Invalid Item with Rules",
            matchingRules: [1, 2],
            exclusionRules: [3]
        )
        let validItemAfterInvalid = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
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
        let itemWithManyRules = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
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
        let firstItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
            id: "duplicate_id",
            titleText: "First Item",
            matchingRules: [1, 2],
            exclusionRules: [3]
        )
        let duplicateItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(
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

@Suite("RMF - Mapping - Cards List With Section")
struct JsonToRemoteMessageModelMapperTitledSectionTests {
    let surveyActionMapper = MockRemoteMessageSurveyActionMapper()

    @Test("Check Valid Titled Section Maps Successfully")
    func validTitledSectionMapsSuccessfully() throws {
        // GIVEN
        let sectionItem = RemoteMessageResponse.JsonListItem.mockSectionItem(
            id: "section1",
            titleText: "New Features",
            itemIDs: ["item1"]
        )
        let item = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1")
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [sectionItem, item])

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        let section = try #require(items.first)
        #expect(section.id == "section1")
        #expect(section.type == .titledSection(titleText: "New Features", itemIDs: ["item1"]))
        #expect(section.titleText == "New Features")
        #expect(section.descriptionText == nil, "Section should not have description")
        #expect(section.placeholderImage == nil, "Section should not have placeholder")
        #expect(section.action == nil, "Section should not have action")
    }

    @Test("Check Titled Section With Empty Title Is Discarded")
    func emptyTitleDiscardsSection() {
        // GIVEN
        let validItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "valid_item")
        let invalidSection = RemoteMessageResponse.JsonListItem.mockSectionItem(id: "section1", titleText: "", itemIDs: ["valid_item"])
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [invalidSection, validItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1, "Invalid section should be discarded")
        #expect(items.first?.id == "valid_item")
    }

    @Test("Check Titled Section With Nil itemIDs Is Discarded")
    func sectionWithoutItemIDsIsDiscarded() {
        // GIVEN - Section without itemIDs field (nil)
        let validItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "valid_item")
        let sectionWithoutItemIDs = RemoteMessageResponse.JsonListItem.mockSectionItem(
            id: "section1",
            titleText: "Section Title",
            itemIDs: nil
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [sectionWithoutItemIDs, validItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN - Section without itemIDs should be discarded
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1, "Section without itemIDs should be discarded")
        #expect(items.first?.id == "valid_item")
    }

    @Test("Check Titled Section With Empty itemIDs Is Discarded")
    func sectionWithEmptyItemIDsIsDiscarded() {
        // GIVEN - Section with empty itemIDs array
        let validItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "valid_item")
        let sectionWithEmptyItemIDs = RemoteMessageResponse.JsonListItem.mockSectionItem(
            id: "section1",
            titleText: "Section Title",
            itemIDs: []
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [sectionWithEmptyItemIDs, validItem])

        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper)

        // THEN - Section with empty itemIDs should be discarded
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 1, "Section with empty itemIDs should be discarded")
        #expect(items.first?.id == "valid_item")
    }

    @Test("Check Titled Section Ignores Description, Placeholder, and Action Fields")
    func sectionIgnoresNonApplicableFields() throws {
        // GIVEN - Section with fields that should be ignored
        let sectionWithExtraFields = RemoteMessageResponse.JsonListItem(
            id: "section1",
            type: "section_title",
            titleText: "Section Title",
            descriptionText: "This should be ignored",
            placeholder: "Announce",
            primaryActionText: "Test Action",
            primaryAction: .urlInContext,
            matchingRules: nil,
            exclusionRules: nil,
            itemIDs: ["item1"]
        )
        let item = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1")
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [sectionWithExtraFields, item])

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        let section = try #require(items.first)
        #expect(section.id == "section1")
        #expect(section.type == .titledSection(titleText: "Section Title", itemIDs: ["item1"]))
        // These should not be part of titledSection
        #expect(section.descriptionText == nil)
        #expect(section.placeholderImage == nil)
        #expect(section.action == nil)
    }

    @Test("Check Mixed List With Sections And Items Maps Correctly")
    func mixedListMapsCorrectly() throws {
        // GIVEN
        let section1 = RemoteMessageResponse.JsonListItem.mockSectionItem(id: "section1", titleText: "Features", itemIDs: ["item1", "item2"])
        let item1 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1", titleText: "Feature 1")
        let item2 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item2", titleText: "Feature 2")
        let section2 = RemoteMessageResponse.JsonListItem.mockSectionItem(id: "section2", titleText: "Improvements", itemIDs: ["item3"])
        let item3 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item3", titleText: "Improvement 1")

        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [section1, item1, item2, section2, item3]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 5)

        // Verify section 1
        let firstSection  = try #require(items[safe: 0])
        #expect(firstSection.id == "section1")
        #expect(firstSection.type == .titledSection(titleText: "Features", itemIDs: ["item1", "item2"]))

        // Verify items under section 1
        let firstItemSection1  = try #require(items[safe: 1])
        let secondItemSection1  = try #require(items[safe: 2])
        #expect(firstItemSection1.id == "item1")
        #expect(firstItemSection1.titleText == "Feature 1")
        #expect(secondItemSection1.id == "item2")
        #expect(secondItemSection1.titleText == "Feature 2")

        // Verify section 2
        let secondSection  = try #require(items[safe: 3])
        #expect(secondSection.id == "section2")
        #expect(secondSection.type == .titledSection(titleText: "Improvements", itemIDs: ["item3"]))

        // Verify item under section 2
        let firstItemSection2 = try #require(items[safe: 4])
        #expect(firstItemSection2.id == "item3")
        #expect(firstItemSection2.titleText == "Improvement 1")
    }

    @Test("Check Duplicate Section IDs Are Handled Correctly")
    func duplicateSectionIDsKeepFirstOccurrence() throws {
        // GIVEN
        let section1 = RemoteMessageResponse.JsonListItem.mockSectionItem(id: "duplicate", titleText: "First Section", itemIDs: ["item1"])
        let item1 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1")
        let section2 = RemoteMessageResponse.JsonListItem.mockSectionItem(id: "duplicate", titleText: "Second Section", itemIDs: ["item2"])
        let item2 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item2")
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [section1, item1, section2, item2])

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 3, "Duplicate ID should be discarded")
        #expect(items[safe: 0]?.id == "duplicate")
        #expect(items[safe: 1]?.id == "item1")
        #expect(items[safe: 2]?.id == "item2")
    }

    @Test("Check Section And Item With Same Id Are Handled Correctly (keep first occurrence)")
    func sectionAndItemWithSameIDKeepsFirst() throws {
        // GIVEN
        let section = RemoteMessageResponse.JsonListItem.mockSectionItem(id: "same_id", titleText: "Section", itemIDs: ["item1"])
        let item1 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "same_id", titleText: "Item")
        let item2 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item2", titleText: "Item")
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [section, item1, item2])

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 2, "Duplicate ID should be discarded")
        #expect(items.first?.type == .titledSection(titleText: "Section", itemIDs: ["item1"]), "Should keep first item encountered")
        #expect(items.last?.id == "item2")
    }

    @Test("Check Section With Valid itemIDs Maps Successfully")
    func sectionWithValidItemIDsMapsSuccessfully() throws {
        // GIVEN - Section with itemIDs referencing existing items
        let item1 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1", titleText: "Feature 1")
        let item2 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item2", titleText: "Feature 2")
        let sectionWithItemIDs = RemoteMessageResponse.JsonListItem.mockSectionItem(
            id: "section1",
            titleText: "Features",
            itemIDs: ["item1", "item2"]
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [sectionWithItemIDs, item1, item2]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN - Section should be mapped with itemIDs
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 3)

        let section = try #require(items.first)
        #expect(section.id == "section1")

        // Verify itemIDs are included in the section
        guard case let .titledSection(titleText, itemIDs) = section.type else {
            Issue.record("Expected titledSection type")
            return
        }

        #expect(titleText == "Features")
        #expect(itemIDs == ["item1", "item2"], "Section should have itemIDs")
    }
}

@Suite("RMF - Mapping - Cards List With Featured Items")
struct JsonToRemoteMessageModelMapperFeaturedItemTests {
    let surveyActionMapper = MockRemoteMessageSurveyActionMapper()

    @Test("Check Single Featured Item Maps Successfully")
    func singleFeaturedItemMapsSuccessfully() throws {
        // GIVEN
        let featuredItem = RemoteMessageResponse.JsonListItem.mockFeaturedItem(id: "featured1", titleText: "Featured Feature")
        let regularItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1")
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [featuredItem, regularItem])

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 2)

        guard case let .featuredTwoLinesSingleActionItem(titleText, descriptionText, placeholderImage, primaryActionText, primaryAction) = items.first?.type else {
            Issue.record("Expected featuredTwoLinesSingleActionItem type")
            return
        }

        #expect(titleText == "Featured Feature")
        #expect(descriptionText == "Description")
        #expect(placeholderImage == .announce)
        #expect(primaryActionText == nil)
        #expect(primaryAction == .urlInContext(value: "https://example.com"))
    }

    @Test("Check Multiple Featured Items - First Kept, Rest Discarded")
    func multipleFeaturedItemsKeepsFirst() throws {
        // GIVEN
        let firstFeatured = RemoteMessageResponse.JsonListItem.mockFeaturedItem(id: "featured1", titleText: "First Featured", primaryActionText: "Learn More")
        let firstRegularItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1")
        let secondFeatured = RemoteMessageResponse.JsonListItem.mockFeaturedItem(id: "featured2", titleText: "Second Featured", primaryActionText: "See Details")
        let secondRegularItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item2")

        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [firstFeatured, firstRegularItem, secondFeatured, secondRegularItem]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 3, "Should keep first featured and both regular items, discard second featured")
        #expect(items[safe: 0]?.id == "featured1")
        #expect(items[safe: 1]?.id == "item1")
        #expect(items[safe: 2]?.id == "item2")
    }

    @Test("Check Featured Item After Regular Items Is Still Kept")
    func featuredItemAfterRegularItemsIsKept() throws {
        // GIVEN
        let regularItem1 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1")
        let regularItem2 = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item2")
        let featuredItem = RemoteMessageResponse.JsonListItem.mockFeaturedItem(id: "featured1", titleText: "Featured")

        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [regularItem1, regularItem2, featuredItem]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 3)
        #expect(items[safe: 0]?.id == "item1")
        #expect(items[safe: 1]?.id == "item2")
        #expect(items[safe: 2]?.id == "featured1")
    }

    @Test("Check Invalid Featured Item Allows Valid Featured Item Later")
    func invalidFeaturedItemAllowsValidFeaturedLater() throws {
        // GIVEN - First featured item is invalid (empty title)
        let invalidFeatured = RemoteMessageResponse.JsonListItem.mockFeaturedItem(id: "invalid", titleText: "")
        let validFeatured = RemoteMessageResponse.JsonListItem.mockFeaturedItem(id: "valid", titleText: "Valid Featured")
        let regularItem = RemoteMessageResponse.JsonListItem.mockTwoLinesListItem(id: "item1")

        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(
            listItems: [invalidFeatured, validFeatured, regularItem]
        )

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        #expect(items.count == 2, "Invalid featured should be discarded, valid featured should be kept")
        #expect(items.first?.id == "valid")
        #expect(items.last?.id == "item1")
    }

    @Test("Check Featured Item With Primary Action Text Maps Correctly")
    func featuredItemWithPrimaryActionText() throws {
        // GIVEN
        let featuredItem = RemoteMessageResponse.JsonListItem.mockFeaturedItem(
            id: "featured1",
            titleText: "New Feature",
            descriptionText: "Check it out",
            primaryActionText: "Try Now"
        )
        let jsonContent = RemoteMessageResponse.JsonContent.mockCardsListMessage(listItems: [featuredItem])

        // WHEN
        let result = try #require(JsonToRemoteMessageModelMapper.mapToContent(content: jsonContent, surveyActionMapper: surveyActionMapper))

        // THEN
        guard case let .cardsList(_, _, items, _, _) = result else {
            Issue.record("Expected cardsList message type")
            return
        }

        guard case let .featuredTwoLinesSingleActionItem(titleText, descriptionText, _, primaryActionText, _) = items.first?.type else {
            Issue.record("Expected featuredTwoLinesSingleActionItem type")
            return
        }

        #expect(titleText == "New Feature")
        #expect(descriptionText == "Check it out")
        #expect(primaryActionText == "Try Now")
    }
}

// MARK: - Helpers

private extension RemoteMessageResponse.JsonContent {

    static func mockCardsListMessage(
        titleText: String = "What's New",
        placeholder: String? = nil,
        listItems: [RemoteMessageResponse.JsonListItem]? = [.mockTwoLinesListItem(id: "item1"), .mockTwoLinesListItem(id: "item2")],
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

    static func mockTwoLinesListItem(
        id: String,
        type: String = "two_line_list_item",
        titleText: String = "Feature",
        descriptionText: String? = "Description",
        placeholder: String? = "Announce",
        primaryActionText: String? = nil,
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
            primaryActionText: primaryActionText,
            primaryAction: primaryAction,
            matchingRules: matchingRules,
            exclusionRules: exclusionRules,
            itemIDs: nil
        )
    }

    static func mockSectionItem(
        id: String,
        titleText: String = "Section Title",
        itemIDs: [String]?
    ) -> RemoteMessageResponse.JsonListItem {
        RemoteMessageResponse.JsonListItem(
            id: id,
            type: "section_title",
            titleText: titleText,
            descriptionText: nil,
            placeholder: nil,
            primaryActionText: nil,
            primaryAction: nil,
            matchingRules: nil,
            exclusionRules: nil,
            itemIDs: itemIDs
        )
    }

    static func mockFeaturedItem(
        id: String,
        titleText: String = "Featured Item",
        descriptionText: String? = "Description",
        placeholder: String? = "Announce",
        primaryActionText: String? = nil,
        primaryAction: RemoteMessageResponse.JsonMessageAction? = .init(type: "url_in_context", value: "https://example.com", additionalParameters: nil),
        matchingRules: [Int]? = nil,
        exclusionRules: [Int]? = nil
    ) -> RemoteMessageResponse.JsonListItem {
        RemoteMessageResponse.JsonListItem(
            id: id,
            type: "featured_two_line_single_action_list_item",
            titleText: titleText,
            descriptionText: descriptionText,
            placeholder: placeholder,
            primaryActionText: primaryActionText,
            primaryAction: primaryAction,
            matchingRules: matchingRules,
            exclusionRules: exclusionRules,
            itemIDs: nil
        )
    }

}

private extension RemoteMessageResponse.JsonMessageAction {
    static let dismiss: RemoteMessageResponse.JsonMessageAction = .init(type: "dismiss", value: "", additionalParameters: nil)
    static let urlInContext: RemoteMessageResponse.JsonMessageAction = .init(type: "url_in_context", value: "https://example.com", additionalParameters: nil)
}
