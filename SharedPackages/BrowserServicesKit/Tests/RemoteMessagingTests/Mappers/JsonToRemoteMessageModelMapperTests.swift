//
//  JsonToRemoteMessageModelMapperTests.swift
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

import XCTest
import RemoteMessagingTestsUtils
@testable import RemoteMessaging

class JsonToRemoteMessageModelMapperTests: XCTestCase {

    func testThatGetTranslationMatchesTheLocale() {
        let translations: [String: RemoteMessageResponse.JsonContentTranslation] = [
            "en-CA": RemoteMessageResponse.JsonContentTranslation(
                messageType: "type",
                titleText: "en-CA-title",
                descriptionText: "en-CA-description",
                primaryActionText: "en-CA-primary",
                secondaryActionText: "en-CA-secondary",
                listItems: [
                    "item-1-id": .init(
                        titleText: "en-CA-list-item-title",
                        descriptionText: "en-CA-list-item-description",
                        primaryActionText: "en-CA-list-item-primaryAction"
                    )
                ]
            ),
            "en": RemoteMessageResponse.JsonContentTranslation(
                messageType: "type",
                titleText: "en-title",
                descriptionText: "en-description",
                primaryActionText: "en-primary",
                secondaryActionText: "en-secondary",
                listItems: [
                    "item-1-id": .init(
                        titleText: "en-list-item-title",
                        descriptionText: "en-list-item-description",
                        primaryActionText: "en-list-item-primaryAction"
                    )
                ]
            ),
        ]

        let locale = Locale.init(identifier: "en-CA")
        let translation = JsonToRemoteMessageModelMapper.getTranslation(from: translations, for: locale)

        XCTAssertNotNil(translation)
        XCTAssertEqual(translation?.titleText, "en-CA-title")
        XCTAssertEqual(translation?.descriptionText, "en-CA-description")
        XCTAssertEqual(translation?.primaryActionText, "en-CA-primary")
        XCTAssertEqual(translation?.secondaryActionText, "en-CA-secondary")
        XCTAssertEqual(translation?.listItems?["item-1-id"]?.titleText, "en-CA-list-item-title")
        XCTAssertEqual(translation?.listItems?["item-1-id"]?.descriptionText, "en-CA-list-item-description")
        XCTAssertEqual(translation?.listItems?["item-1-id"]?.primaryActionText, "en-CA-list-item-primaryAction")
    }

    func testThatGetTranslationReturnsGenericTranslationWhenOnlyLanguageMatches() {
        let translations: [String: RemoteMessageResponse.JsonContentTranslation] = [
            "en-CA": RemoteMessageResponse.JsonContentTranslation(
                messageType: "type",
                titleText: "en-CA-title",
                descriptionText: "en-CA-description",
                primaryActionText: "en-CA-primary",
                secondaryActionText: "en-CA-secondary",
                listItems: [
                    "item-1-id": .init(
                        titleText: "en-CA-list-item-title",
                        descriptionText: "en-CA-list-item-description",
                        primaryActionText: "en-CA-list-item-primaryAction"
                    )
                ]
            ),
            "en": RemoteMessageResponse.JsonContentTranslation(
                messageType: "type",
                titleText: "en-title",
                descriptionText: "en-description",
                primaryActionText: "en-primary",
                secondaryActionText: "en-secondary",
                listItems: [
                    "item-1-id": .init(
                        titleText: "en-list-item-title",
                        descriptionText: "en-list-item-description",
                        primaryActionText: "en-list-item-primaryAction"
                    )
                ]
            ),
        ]

        let locale = Locale.init(identifier: "en-US")
        let translation = JsonToRemoteMessageModelMapper.getTranslation(from: translations, for: locale)

        XCTAssertNotNil(translation)
        XCTAssertEqual(translation?.titleText, "en-title")
        XCTAssertEqual(translation?.descriptionText, "en-description")
        XCTAssertEqual(translation?.primaryActionText, "en-primary")
        XCTAssertEqual(translation?.secondaryActionText, "en-secondary")
        XCTAssertEqual(translation?.listItems?["item-1-id"]?.titleText, "en-list-item-title")
        XCTAssertEqual(translation?.listItems?["item-1-id"]?.descriptionText, "en-list-item-description")
        XCTAssertEqual(translation?.listItems?["item-1-id"]?.primaryActionText, "en-list-item-primaryAction")
    }

    // MARK: - CardsList Translation Tests

    func testThatCardsListTranslatesListItems() {
        // GIVEN
        let item1 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", titleText: "Original Title 1", descriptionText: "Original Description 1")
        let item2 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", titleText: "Original Title 2", descriptionText: "Original Description 2")
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [item1, item2], primaryActionText: "Original Primary Action")

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title 1",
                descriptionText: "Translated Description 1",
                primaryActionText: nil
            ),
            "item2": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title 2",
                descriptionText: "Translated Description 2",
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(titleText: "Translated Message Title", primaryActionText: "Translated Button", listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(titleText, _, items, primaryActionText, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(titleText, "Translated Message Title")
        XCTAssertEqual(primaryActionText, "Translated Button")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.titleText, "Translated Title 1")
        XCTAssertEqual(items.first?.descriptionText, "Translated Description 1")
        XCTAssertEqual(items.last?.titleText, "Translated Title 2")
        XCTAssertEqual(items.last?.descriptionText, "Translated Description 2")
    }

    func testThatCardsListPreservesUntranslatedItemsWhenNoTranslationProvided() {
        // GIVEN
        let item1 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", titleText: "Original Item Title 1", descriptionText: "Original Item Description 1")
        let item2 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", titleText: "Original Item Title 2", descriptionText: "Original Item Description 2")
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [item1, item2], primaryActionText: "Original Primary Action")
        // Translate only item1, not item2
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Item Title 1",
                descriptionText: "Translated Item Description 1",
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(items.count, 2)
        // Item 1 should be translated
        XCTAssertEqual(items.first?.titleText, "Translated Item Title 1")
        XCTAssertEqual(items.first?.descriptionText, "Translated Item Description 1")
        // Item 2 should remain original
        XCTAssertEqual(items.last?.titleText, "Original Item Title 2")
        XCTAssertEqual(items.last?.descriptionText, "Original Item Description 2")
    }

    func testThatCardsListFallsBackToOriginalTitleAndDescriptionWhenTranslationNil() {
        // GIVEN
        let item = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", titleText: "Original Item Title", descriptionText: "Original Item Description")
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [item], primaryActionText: "Original Primary Action")
        // Translation with nil titleText and descriptionText
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: nil, // Nil title should fall back to original
                descriptionText: nil,  // Nil description should fall back to original
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(items.first?.titleText, "Original Item Title")
        XCTAssertEqual(items.first?.descriptionText, "Original Item Description")
    }

    func testThatCardsListPreservesNonTranslatableFields() throws {
        // GIVEN
        let item = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", titleText: "Original Title", descriptionText: "Original Description", placeholder: .keyImport, action: .urlInContext(value: "www.duckduckgo.com"), matchingRules: [5], exclusionRules: [6])
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", placeholder: .ddgAnnounce, items: [item], primaryActionText: "Original Primary Action", primaryAction: .dismiss)
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title",
                descriptionText: "Translated Description",
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(titleText, placeholder, items, primaryActionText, primaryAction) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        // Message preserved fields
        XCTAssertEqual(titleText, "Original Title")
        XCTAssertEqual(placeholder, .ddgAnnounce)
        XCTAssertEqual(primaryActionText, "Original Primary Action")
        XCTAssertEqual(primaryAction, .dismiss)

        // Message Item fields
        let firstItem = try XCTUnwrap(items.first)
        XCTAssertEqual(firstItem.id, "item1")
        XCTAssertEqual(
            firstItem.type,
            .twoLinesItem(
                titleText: "Translated Title",
                descriptionText: "Translated Description",
                placeholderImage: .keyImport,
                action: .urlInContext(value: "www.duckduckgo.com")
            )
        )
        XCTAssertEqual(firstItem.matchingRules, [5])
        XCTAssertEqual(firstItem.exclusionRules, [6])
    }

    // MARK: - TitledSection Translation Tests

    func testThatTitledSectionTranslatesTitleCorrectly() {
        // GIVEN
        let section = RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Original Section Title")
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [section], primaryActionText: "Done")

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "section1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Section Title",
                descriptionText: nil,
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(items.first?.titleText, "Translated Section Title")
    }

    func testThatTitledSectionFallsBackToOriginalWhenTranslationIsNil() {
        // GIVEN
        let section = RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Original Section Title")
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [section], primaryActionText: "Done")

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "section1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: nil,
                descriptionText: nil,
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(items.first?.titleText, "Original Section Title")
    }

    func testThatTitledSectionPreservesNonTranslatableFields() throws {
        // GIVEN
        let section = RemoteMessageModelType.ListItem.makeTitledSectionListItem(
            id: "section1",
            titleText: "Original Section Title",
            itemIDs: ["item1"]
        )
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [section], primaryActionText: "Done")

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "section1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Section Title",
                descriptionText: nil,
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        let firstItem = try XCTUnwrap(items.first)
        XCTAssertEqual(firstItem.id, "section1")
        XCTAssertEqual(firstItem.type, .titledSection(titleText: "Translated Section Title", itemIDs: ["item1"]))
    }

    func testThatMixedListWithBothItemTypesTranslatesCorrectly() throws {
        // GIVEN
        let section = RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Original Section")
        let item1 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", titleText: "Original Item 1", descriptionText: "Original Description 1")
        let item2 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item2", titleText: "Original Item 2", descriptionText: "Original Description 2")
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [section, item1, item2], primaryActionText: "Done")

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "section1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Section",
                descriptionText: nil,
                primaryActionText: nil
            ),
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Item 1",
                descriptionText: "Translated Description 1",
                primaryActionText: nil
            ),
            "item2": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Item 2",
                descriptionText: "Translated Description 2",
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(items.count, 3)
        let resultSection = try XCTUnwrap(items[safe: 0])
        let resultItem1 = try XCTUnwrap(items[safe: 1])
        let resultItem2 = try XCTUnwrap(items[safe: 2])

        // Verify section
        XCTAssertEqual(resultSection.titleText, "Translated Section")
        XCTAssertNil(resultSection.descriptionText, "Section should not have description")

        // Verify items
        XCTAssertEqual(resultItem1.titleText, "Translated Item 1")
        XCTAssertEqual(resultItem1.descriptionText, "Translated Description 1")
        XCTAssertEqual(resultItem2.titleText, "Translated Item 2")
        XCTAssertEqual(resultItem2.descriptionText, "Translated Description 2")
    }

    func testThatMixedListWithPartialTranslationWorks() {
        // GIVEN
        let section = RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Original Section")
        let item1 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", titleText: "Original Item 1", descriptionText: "Original Description 1")
        var message = RemoteMessageModel.makeCardsListMessage(id: "test", titleText: "Original Title", items: [section, item1], primaryActionText: "Done")

        // Only translate the section, not the item
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "section1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Section",
                descriptionText: nil,
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(items.count, 2)

        // Section should be translated
        XCTAssertEqual(items.first?.titleText, "Translated Section")

        // Item should remain original
        XCTAssertEqual(items.last?.titleText, "Original Item 1")
        XCTAssertEqual(items.last?.descriptionText, "Original Description 1")
    }

    // MARK: - Featured Item Translation Tests

    func testThatFeaturedItemTranslatesAllFieldsCorrectly() throws {
        // GIVEN
        let featuredItem = RemoteMessageModelType.ListItem.makeFeaturedItem(
            id: "featured1",
            titleText: "Original Featured Title",
            descriptionText: "Original Featured Description",
            primaryActionText: "Original Action"
        )
        var message = RemoteMessageModel.makeCardsListMessage(
            id: "test",
            titleText: "Original Title",
            items: [featuredItem],
            primaryActionText: "Done"
        )

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "featured1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Featured Title",
                descriptionText: "Translated Featured Description",
                primaryActionText: "Translated Action"
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        let firstItem = try XCTUnwrap(items.first)
        XCTAssertEqual(firstItem.titleText, "Translated Featured Title")
        XCTAssertEqual(firstItem.descriptionText, "Translated Featured Description")
        XCTAssertEqual(firstItem.primaryActionText, "Translated Action")
    }

    func testThatFeaturedItemFallsBackToOriginalWhenTranslationIsNil() throws {
        // GIVEN
        let featuredItem = RemoteMessageModelType.ListItem.makeFeaturedItem(
            id: "featured1",
            titleText: "Original Featured Title",
            descriptionText: "Original Featured Description",
            primaryActionText: "Original Action"
        )
        var message = RemoteMessageModel.makeCardsListMessage(
            id: "test",
            titleText: "Original Title",
            items: [featuredItem],
            primaryActionText: "Done"
        )

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "featured1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: nil,
                descriptionText: nil,
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        let firstItem = try XCTUnwrap(items.first)
        XCTAssertEqual(firstItem.titleText, "Original Featured Title")
        XCTAssertEqual(firstItem.descriptionText, "Original Featured Description")
        XCTAssertEqual(firstItem.primaryActionText, "Original Action")
    }

    func testThatFeaturedItemPreservesNonTranslatableFields() throws {
        // GIVEN
        let featuredItem = RemoteMessageModelType.ListItem.makeFeaturedItem(
            id: "featured1",
            titleText: "Original Title",
            descriptionText: "Original Description",
            placeholder: .visualDesignUpdate,
            primaryActionText: "Original Action",
            primaryAction: .navigation(value: .settings),
            matchingRules: [7],
            exclusionRules: [8]
        )
        var message = RemoteMessageModel.makeCardsListMessage(
            id: "test",
            titleText: "Original Title",
            items: [featuredItem],
            primaryActionText: "Done"
        )

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "featured1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title",
                descriptionText: "Translated Description",
                primaryActionText: "Translated Action"
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        let firstItem = try XCTUnwrap(items.first)
        XCTAssertEqual(firstItem.id, "featured1")
        XCTAssertEqual(
            firstItem.type,
            .featuredTwoLinesSingleActionItem(
                titleText: "Translated Title",
                descriptionText: "Translated Description",
                placeholderImage: .visualDesignUpdate,
                primaryActionText: "Translated Action",
                primaryAction: .navigation(value: .settings)
            )
        )
        XCTAssertEqual(firstItem.matchingRules, [7])
        XCTAssertEqual(firstItem.exclusionRules, [8])
    }

    func testThatFeaturedItemPartiallyTranslatesFields() throws {
        // GIVEN
        let featuredItem = RemoteMessageModelType.ListItem.makeFeaturedItem(
            id: "featured1",
            titleText: "Original Title",
            descriptionText: "Original Description",
            primaryActionText: "Original Action"
        )
        var message = RemoteMessageModel.makeCardsListMessage(
            id: "test",
            titleText: "Original Title",
            items: [featuredItem],
            primaryActionText: "Done"
        )

        // Only translate title and primaryActionText, leave description as original
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "featured1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title",
                descriptionText: nil,
                primaryActionText: "Translated Action"
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        let firstItem = try XCTUnwrap(items.first)
        XCTAssertEqual(firstItem.titleText, "Translated Title")
        XCTAssertEqual(firstItem.descriptionText, "Original Description")
        XCTAssertEqual(firstItem.primaryActionText, "Translated Action")
    }

    func testThatMixedListWithFeaturedItemsTranslatesCorrectly() throws {
        // GIVEN
        let featuredItem = RemoteMessageModelType.ListItem.makeFeaturedItem(
            id: "featured1",
            titleText: "Original Featured",
            descriptionText: "Original Featured Description",
            primaryActionText: "Original Featured Action"
        )
        let section = RemoteMessageModelType.ListItem.makeTitledSectionListItem(id: "section1", titleText: "Original Section")
        let item1 = RemoteMessageModelType.ListItem.makeTwoLinesListItem(id: "item1", titleText: "Original Item 1", descriptionText: "Original Description 1")
        var message = RemoteMessageModel.makeCardsListMessage(
            id: "test",
            titleText: "Original Title",
            items: [featuredItem, section, item1],
            primaryActionText: "Done"
        )

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "featured1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Featured",
                descriptionText: "Translated Featured Description",
                primaryActionText: "Translated Featured Action"
            ),
            "section1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Section",
                descriptionText: nil,
                primaryActionText: nil
            ),
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Item 1",
                descriptionText: "Translated Description 1",
                primaryActionText: nil
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, _, items, _, _) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        XCTAssertEqual(items.count, 3)
        let resultFeatured = try XCTUnwrap(items[safe: 0])
        let resultSection = try XCTUnwrap(items[safe: 1])
        let resultItem = try XCTUnwrap(items[safe: 2])

        // Verify featured item
        XCTAssertEqual(resultFeatured.titleText, "Translated Featured")
        XCTAssertEqual(resultFeatured.descriptionText, "Translated Featured Description")
        XCTAssertEqual(resultFeatured.primaryActionText, "Translated Featured Action")

        // Verify section
        XCTAssertEqual(resultSection.titleText, "Translated Section")

        // Verify regular item
        XCTAssertEqual(resultItem.titleText, "Translated Item 1")
        XCTAssertEqual(resultItem.descriptionText, "Translated Description 1")
    }

}

extension JsonToRemoteMessageModelMapperTests {

    func jsonTranslation(
        titleText: String? = nil,
        descriptionText: String? = nil,
        primaryActionText: String? = nil,
        secondaryActionText: String? = nil,
        listItems: [String: RemoteMessageResponse.JsonListItemTranslation]? = nil
    ) -> RemoteMessageResponse.JsonContentTranslation {
        RemoteMessageResponse.JsonContentTranslation(
            messageType: nil,
            titleText: titleText,
            descriptionText: descriptionText,
            primaryActionText: primaryActionText,
            secondaryActionText: secondaryActionText,
            listItems: listItems
        )
    }

}
