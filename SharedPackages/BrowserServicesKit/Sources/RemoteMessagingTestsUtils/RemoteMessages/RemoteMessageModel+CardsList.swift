//
//  RemoteMessageModel+CardsList.swift
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
import RemoteMessaging

public extension RemoteMessageModel {

    static func makeCardsListMessage(
        id: String = "test-message-id",
        titleText: String = "List Title",
        placeholder: RemotePlaceholder? = nil,
        imageUrl: URL? = nil,
        items: [RemoteMessageModelType.ListItem] = [],
        primaryActionText: String = "Done",
        primaryAction: RemoteAction = .dismiss
    ) -> RemoteMessageModel {
        let content: RemoteMessageModelType = .cardsList(
            titleText: titleText,
            placeholder: placeholder,
            imageUrl: imageUrl,
            items: items,
            primaryActionText: primaryActionText,
            primaryAction: primaryAction
        )

        return RemoteMessageModel(
            id: id,
            surfaces: .modal,
            content: content,
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: true
        )
    }

}

public extension RemoteMessageModelType.ListItem {

    static func makeTwoLinesListItem(
        id: String = "item-1",
        titleText: String = "Item Title",
        descriptionText: String = "Item Description",
        placeholder: RemotePlaceholder = .announce,
        action: RemoteAction? = nil,
        matchingRules: [Int] = [],
        exclusionRules: [Int] = []
    ) -> RemoteMessageModelType.ListItem {
        RemoteMessageModelType.ListItem(
            id: id,
            type: .twoLinesItem(
                titleText: titleText,
                descriptionText: descriptionText,
                placeholderImage: placeholder,
                action: action
            ),
            matchingRules: matchingRules,
            exclusionRules: exclusionRules
        )
    }

    static func makeTitledSectionListItem(
        id: String = "section-1",
        titleText: String = "Section Title",
        itemIDs: [String] = []
    ) -> RemoteMessageModelType.ListItem {
        RemoteMessageModelType.ListItem(
            id: id,
            type: .titledSection(titleText: titleText, itemIDs: itemIDs),
            matchingRules: [],
            exclusionRules: []
        )
    }

    static func makeFeaturedItem(
        id: String = "featured-1",
        titleText: String = "Featured Item",
        descriptionText: String = "Featured Description",
        placeholder: RemotePlaceholder = .announce,
        primaryActionText: String? = nil,
        primaryAction: RemoteAction? = nil,
        matchingRules: [Int] = [],
        exclusionRules: [Int] = []
    ) -> RemoteMessageModelType.ListItem {
        RemoteMessageModelType.ListItem(
            id: id,
            type: .featuredTwoLinesSingleActionItem(
                titleText: titleText,
                descriptionText: descriptionText,
                placeholderImage: placeholder,
                primaryActionText: primaryActionText,
                primaryAction: primaryAction
            ),
            matchingRules: matchingRules,
            exclusionRules: exclusionRules
        )
    }
}

public extension RemoteMessageModelType.ListItem {

    var titleText: String? {
        switch type {
        case let .titledSection(titleText, _):
            return titleText
        case let .twoLinesItem(titleText, _, _, _):
            return titleText
        case let .featuredTwoLinesSingleActionItem(titleText, _, _, _, _):
            return titleText
        }
    }

    var descriptionText: String? {
        switch type {
        case .titledSection:
            return nil
        case let .twoLinesItem(_, descriptionText, _, _):
            return descriptionText
        case let .featuredTwoLinesSingleActionItem(_, descriptionText, _, _, _):
            return descriptionText
        }
    }

    var placeholderImage: RemotePlaceholder? {
        switch type {
        case .titledSection:
            return nil
        case let .twoLinesItem(_, _, placeholderImage, _):
            return placeholderImage
        case let .featuredTwoLinesSingleActionItem(_, _, placeholderImage, _, _):
            return placeholderImage
        }
    }

    var primaryActionText: String? {
        switch type {
        case.titledSection, .twoLinesItem:
            return nil
        case let .featuredTwoLinesSingleActionItem(_, _, _, primaryActionText, _):
            return primaryActionText
        }
    }

    var action: RemoteAction? {
        switch type {
        case .titledSection:
            return nil
        case let .twoLinesItem(_, _, _, action):
            return action
        case let .featuredTwoLinesSingleActionItem(_, _, _, _, action):
            return action
        }
    }

}
