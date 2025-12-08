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
                        descriptionText: "en-CA-list-item-description"
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
                        descriptionText: "en-list-item-description"
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
                        descriptionText: "en-CA-list-item-description"
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
                        descriptionText: "en-list-item-description"
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
    }

    // MARK: - CardsList Translation Tests

    func testThatCardsListTranslatesListItems() {
        // GIVEN
        let item1 = listItem(id: "item1", titleText: "Original Title 1", descriptionText: "Original Description 1")
        let item2 = listItem(id: "item2", titleText: "Original Title 2", descriptionText: "Original Description 2")
        var message = cardsListMessage(id: "test", titleText: "Original Title", items: [item1, item2], primaryActionText: "Original Primary Action")

        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title 1",
                descriptionText: "Translated Description 1"
            ),
            "item2": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title 2",
                descriptionText: "Translated Description 2"
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
        let item1 = listItem(id: "item1", titleText: "Original Item Title 1", descriptionText: "Original Item Description 1")
        let item2 = listItem(id: "item2", titleText: "Original Item Title 2", descriptionText: "Original Item Description 2")
        var message = cardsListMessage(id: "test", titleText: "Original Title", items: [item1, item2], primaryActionText: "Original Primary Action")
        // Translate only item1, not item2
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Item Title 1",
                descriptionText: "Translated Item Description 1"
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
        let item = listItem(id: "item1", titleText: "Original Item Title", descriptionText: "Original Item Description")
        var message = cardsListMessage(id: "test", titleText: "Original Title", items: [item], primaryActionText: "Original Primary Action")
        // Translation with nil titleText and descriptionText
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: nil, // Nil title should fall back to original
                descriptionText: nil  // Nil description should fall back to original
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
        let item = listItem(id: "item1", titleText: "Original Title", descriptionText: "Original Description")
        var message = cardsListMessage(id: "test", titleText: "Original Title", items: [item], primaryActionText: "Original Primary Action")
        let translatedItems: [String: RemoteMessageResponse.JsonListItemTranslation] = [
            "item1": RemoteMessageResponse.JsonListItemTranslation(
                titleText: "Translated Title",
                descriptionText: "Translated Description"
            )
        ]
        let translation = jsonTranslation(listItems: translatedItems)

        // WHEN
        message.localizeContent(translation: translation)

        // THEN
        guard case let .cardsList(_, placeholder, items, _, primaryAction) = message.content else {
            XCTFail("Expected cardsList content")
            return
        }

        // Text should be translated
        XCTAssertEqual(placeholder, .ddgAnnounce)
        XCTAssertEqual(primaryAction, .dismiss)

        let firstItem = try XCTUnwrap(items.first)
        XCTAssertEqual(firstItem.id, "item1")
        XCTAssertEqual(firstItem.titleText, "Translated Title")
        XCTAssertEqual(firstItem.descriptionText, "Translated Description")
        XCTAssertEqual(firstItem.type, .twoLinesItem)
        XCTAssertEqual(firstItem.placeholderImage, .keyImport)
        XCTAssertEqual(firstItem.action, .urlInContext(value: "www.duckduckgo.com"))
        XCTAssertEqual(firstItem.matchingRules, [5])
        XCTAssertEqual(firstItem.exclusionRules, [6])
    }

}

extension JsonToRemoteMessageModelMapperTests {

    func listItem(
        id: String,
        titleText: String,
        descriptionText: String
    ) -> RemoteMessageModelType.ListItem {
        RemoteMessageModelType.ListItem(
            id: id,
            type: .twoLinesItem,
            titleText: titleText,
            descriptionText: descriptionText,
            placeholderImage: .keyImport,
            action: .urlInContext(value: "www.duckduckgo.com"),
            matchingRules: [5],
            exclusionRules: [6]
        )
    }

    func cardsListMessage(
        id: String,
        titleText: String,
        items: [RemoteMessageModelType.ListItem],
        primaryActionText: String
    ) -> RemoteMessageModel {
        RemoteMessageModel(
            id: id,
            surfaces: .modal,
            content: .cardsList(
                titleText: titleText,
                placeholder: .ddgAnnounce,
                items: items,
                primaryActionText: primaryActionText,
                primaryAction: .dismiss
            ),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true
        )
    }

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
