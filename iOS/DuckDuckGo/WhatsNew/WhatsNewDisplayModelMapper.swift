//
//  WhatsNewDisplayModelMapper.swift
//  DuckDuckGo
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

import SwiftUI
import DesignResourcesKitIcons
import RemoteMessaging

protocol WhatsNewDisplayModelMapping {
    func makeDisplayModel(
        from message: RemoteMessageModel,
        onMessageAppear: @escaping () -> Void,
        onItemAppear: @escaping (_ itemId: String) -> Void,
        onItemAction: @escaping (_ action: RemoteAction, _ itemId: String) async -> Void,
        onPrimaryAction: @escaping (RemoteAction) async -> Void,
        onDismiss: @escaping () -> Void
    ) -> RemoteMessagingUI.CardsListDisplayModel?
}

struct WhatsNewDisplayModelMapper: WhatsNewDisplayModelMapping {

    /// Maps a RemoteMessageModel to CardsListDisplayModel
    /// Returns nil if message is not a cardsList type
    /// - Parameters:
    ///   - message: The remote message to map
    ///   - onItemAction: Closure called when an item action is tapped
    ///   - onPrimaryAction: Closure called when the primary action is tapped
    ///   - onDismiss: Closure called after primary action completes
    /// - Returns: CardsListDisplayModel if message is cardsList, nil otherwise
    func makeDisplayModel(
        from message: RemoteMessageModel,
        onMessageAppear: @escaping () -> Void,
        onItemAppear: @escaping (_ itemId: String) -> Void,
        onItemAction: @escaping (_ action: RemoteAction, _ itemId: String) async -> Void,
        onPrimaryAction: @escaping (RemoteAction) async -> Void,
        onDismiss: @escaping () -> Void
    ) -> RemoteMessagingUI.CardsListDisplayModel? {

        func mapRemoteListItems(_ remoteListItems: [RemoteMessageModelType.ListItem]) -> [RemoteMessagingUI.CardsListDisplayModel.Item] {
            // Map items to display model items
            remoteListItems.map { remoteListItem in
                switch remoteListItem.type {
                    // Map Title Section Item
                case let .titledSection(titleText, _):
                    return RemoteMessagingUI.CardsListDisplayModel.Item.section(title: titleText)
                    // Map Featured Two Lines Card Item
                case let .featuredTwoLinesSingleActionItem(titleText, descriptionText, placeholderImage, primaryActionText, primaryAction):
                    let featuredTwoLinesCard = RemoteMessagingUI.CardsListDisplayModel.Item.FeaturedTwoLinesCard(
                        icon: placeholderImage.rawValue,
                        title: titleText,
                        description: descriptionText,
                        actionButtonTitle: primaryActionText,
                        onAppear: {
                            onItemAppear(remoteListItem.id)
                        },
                        onTapAction: primaryAction.map { action in
                            makeAction(for: action, itemId: remoteListItem.id, handler: onItemAction)
                        }
                    )
                    return RemoteMessagingUI.CardsListDisplayModel.Item.featuredTwoLinesCard(featuredTwoLinesCard)
                    // Map Two Lines Card Item
                case let .twoLinesItem(titleText, descriptionText, placeholderImage, action):
                    let disclosureIcon = action != nil ? Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronRightSmall) : nil
                    let twoLinesCard = RemoteMessagingUI.CardsListDisplayModel.Item.TwoLinesCard(
                        icon: placeholderImage.rawValue,
                        title: titleText,
                        description: descriptionText,
                        disclosureIcon: disclosureIcon,
                        onAppear: {
                            onItemAppear(remoteListItem.id)
                        },
                        onTapAction: action.map { action in
                            makeAction(for: action, itemId: remoteListItem.id, handler: onItemAction)
                        }
                    )
                    return RemoteMessagingUI.CardsListDisplayModel.Item.twoLinesCard(twoLinesCard)
                }
            }
        }

        guard
            let contentType = message.content,
            case let .cardsList(mainTitleText, placeholder, items, primaryActionText, primaryAction) = contentType
        else {
            return nil
        }

        let listItems = mapRemoteListItems(items)

        return RemoteMessagingUI.CardsListDisplayModel(
            screenTitle: mainTitleText,
            icon: placeholder?.rawValue,
            items: listItems,
            onAppear: onMessageAppear,
            primaryAction: (
                title: primaryActionText,
                action: makeAction(for: primaryAction, handler: onPrimaryAction, andDismiss: onDismiss)
            )
        )
    }

    // MARK: - Private

    // For actions without ID (primary action)
    private func makeAction(
        for remoteAction: RemoteAction,
        handler: @escaping (RemoteAction) async -> Void,
        andDismiss dismissAction: (() -> Void)? = nil
    ) -> () -> Void {
        return {
            Task { @MainActor in
                await handler(remoteAction)
                dismissAction?()
            }
        }
    }

    // For actions with ID (item actions)
    private func makeAction(
        for remoteAction: RemoteAction,
        itemId: String,
        handler: @escaping (RemoteAction, String) async -> Void
    ) -> () -> Void {
        return {
            Task { @MainActor in
                await handler(remoteAction, itemId)
            }
        }
    }

}
