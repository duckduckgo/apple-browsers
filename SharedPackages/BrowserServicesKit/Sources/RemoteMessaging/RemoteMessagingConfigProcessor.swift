//
//  RemoteMessagingConfigProcessor.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Common
import os.log

/**
 * This protocol defines API for processing RMF config file
 * in order to find a message to be displayed.
 */
public protocol RemoteMessagingConfigProcessing {
    var remoteMessagingConfigMatcher: RemoteMessagingConfigMatcher { get }

    func shouldProcessConfig(_ currentConfig: RemoteMessagingConfig?) -> Bool

    func process(
        jsonRemoteMessagingConfig: RemoteMessageResponse.JsonRemoteMessagingConfig,
        currentConfig: RemoteMessagingConfig?,
        supportedSurfacesForMessage: @escaping (RemoteMessageModelType) -> RemoteMessageSurfaceType
    ) -> RemoteMessagingConfigProcessor.ProcessorResult?
}

public struct RemoteMessagingConfigProcessor: RemoteMessagingConfigProcessing {

    public struct ProcessorResult {
        public let version: Int64
        public let message: RemoteMessageModel?
    }

    public let remoteMessagingConfigMatcher: RemoteMessagingConfigMatcher

    public func process(jsonRemoteMessagingConfig: RemoteMessageResponse.JsonRemoteMessagingConfig,
                        currentConfig: RemoteMessagingConfig?,
                        supportedSurfacesForMessage: @escaping (RemoteMessageModelType) -> RemoteMessageSurfaceType
    ) -> ProcessorResult? {
        Logger.remoteMessaging.debug("Processing version \(jsonRemoteMessagingConfig.version, privacy: .public)")

        let currentVersion = currentConfig?.version ?? 0
        let newVersion     = jsonRemoteMessagingConfig.version

        let isNewVersion = newVersion != currentVersion

        if isNewVersion || shouldProcessConfig(currentConfig) {
            let config = JsonToRemoteConfigModelMapper.mapJson(
                remoteMessagingConfig: jsonRemoteMessagingConfig,
                surveyActionMapper: remoteMessagingConfigMatcher.surveyActionMapper,
                supportedSurfacesForMessage: supportedSurfacesForMessage
            )
            let message = remoteMessagingConfigMatcher.evaluate(remoteConfig: config)

            // Reorder items to place featured item first if needed, otherwise return the same message.
            let presentableMessage = moveFeaturedItemToFirstPositionIfNeeded(message: message)

            Logger.remoteMessaging.debug("Message to present next: \(presentableMessage.debugDescription, privacy: .public)")

            return ProcessorResult(version: jsonRemoteMessagingConfig.version, message: presentableMessage)
        }

        return nil
    }

    public func shouldProcessConfig(_ currentConfig: RemoteMessagingConfig?) -> Bool {
        guard let currentConfig = currentConfig else {
            return true
        }

        return currentConfig.invalidate || currentConfig.expired()
    }
}

// MARK: - Remote Message More

private extension RemoteMessagingConfigProcessor {

    func moveFeaturedItemToFirstPositionIfNeeded(message: RemoteMessageModel?) -> RemoteMessageModel? {

        func reorderedListItems(_ items: [RemoteMessageModelType.ListItem]) -> [RemoteMessageModelType.ListItem] {
            // If message does not have a featured item or the featured item appears at the first position return the message unchanged
            guard
                let featuredIndex = items.firstIndex(where: \.type.isFeaturedItem),
                featuredIndex != 0
            else {
                return items
            }

            // Move featured item to first position
            var reordered = items
            let featuredItem = reordered.remove(at: featuredIndex)
            reordered.insert(featuredItem, at: 0)
            return reordered
        }

        // Exit early if the message is nil
        guard let message else { return nil }

        // If message is not a list item return the message unchanged
        guard let items = message.content?.listItems else {
            return message
        }

        // If message is a list item but there are no featured items, return the message unchanged
        guard items.contains(where: \.type.isFeaturedItem) else {
            return message
        }

        // Reorder with featured item first
        let reorderedItems = reorderedListItems(items)

        return message.withNewItems(reorderedItems)
    }

}
