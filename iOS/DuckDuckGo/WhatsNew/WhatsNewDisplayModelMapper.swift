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

@MainActor
struct WhatsNewDisplayModelMapper {

    /// Maps a RemoteMessageModel to CardsListDisplayModel
    /// Returns nil if message is not a cardsList type
    /// - Parameters:
    ///   - message: The remote message to map
    ///   - onItemAction: Closure called when an item action is tapped
    ///   - onPrimaryAction: Closure called when the primary action is tapped
    ///   - onDismiss: Closure called after primary action completes
    /// - Returns: CardsListDisplayModel if message is cardsList, nil otherwise
    static func makeDisplayModel(
        from message: RemoteMessageModel,
        onItemAction: @escaping (RemoteAction) async -> Void,
        onPrimaryAction: @escaping (RemoteAction) async -> Void,
        onDismiss: @escaping () -> Void
    ) -> RemoteMessagingUI.CardsListDisplayModel? {

        guard
            let contentType = message.content,
            case let .cardsList(mainTitleText, items, primaryActionText, primaryAction) = contentType
        else {
            return nil
        }

        // Map items to display model items
        let promoItems = items.map { remoteListItem in
            let disclosureIcon = remoteListItem.action != nil ? Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronRightSmall) : nil

            return RemoteMessagingUI.CardsListDisplayModel.Item(
                icon: Image(remoteListItem.placeholderImage.rawValue),
                title: remoteListItem.titleText,
                description: remoteListItem.descriptionText,
                disclosureIcon: disclosureIcon,
                onTapAction: remoteListItem.action.map { action in
                    makeAction(for: action, handler: onItemAction)
                }
            )
        }

        return RemoteMessagingUI.CardsListDisplayModel(
            screenTitle: mainTitleText,
            items: promoItems,
            onAppear: nil,
            primaryAction: (
                title: primaryActionText,
                action: makeAction(for: primaryAction, handler: onPrimaryAction, andDismiss: onDismiss)
            )
        )
    }

    // MARK: - Private

    /// Creates an action closure for a RemoteAction
    /// - Parameters:
    ///   - remoteAction: The remote action to wrap
    ///   - handler: The async handler to call with the action
    ///   - dismissAction: Optional dismiss closure to call after handler completes
    /// - Returns: A synchronous closure that triggers async action handling
    private static func makeAction(
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
}
