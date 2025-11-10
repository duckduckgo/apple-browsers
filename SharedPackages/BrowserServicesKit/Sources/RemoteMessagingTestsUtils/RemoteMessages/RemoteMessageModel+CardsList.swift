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
        items: [RemoteMessageModelType.ListItem] = [],
        primaryActionText: String = "Done",
        primaryAction: RemoteAction = .dismiss
    ) -> RemoteMessageModel {
        let content: RemoteMessageModelType = .cardsList(
            titleText: titleText,
            placeholder: placeholder,
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

    static func makeListItem(
        id: String = "item-1",
        type: ListItemType = .twoLinesItem,
        titleText: String = "Item Title",
        descriptionText: String = "Item Description",
        placeholder: RemotePlaceholder = .announce,
        action: RemoteAction? = nil
    ) -> RemoteMessageModelType.ListItem {
        return RemoteMessageModelType.ListItem(
            id: id,
            type: type,
            titleText: titleText,
            descriptionText: descriptionText,
            placeholderImage: placeholder,
            action: action,
            matchingRules: [],
            exclusionRules: []
        )
    }
}
