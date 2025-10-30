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
        currentConfig: RemoteMessagingConfig?
    ) -> RemoteMessagingConfigProcessor.ProcessorResult?
}

public struct RemoteMessagingConfigProcessor: RemoteMessagingConfigProcessing {

    public struct ProcessorResult {
        public let version: Int64
        public let message: RemoteMessageModel?
    }

    public let remoteMessagingConfigMatcher: RemoteMessagingConfigMatcher

    public func process(jsonRemoteMessagingConfig: RemoteMessageResponse.JsonRemoteMessagingConfig,
                        currentConfig: RemoteMessagingConfig?) -> ProcessorResult? {
        Logger.remoteMessaging.debug("Processing version \(jsonRemoteMessagingConfig.version, privacy: .public)")

        let currentVersion = currentConfig?.version ?? 0
        let newVersion     = jsonRemoteMessagingConfig.version

        let isNewVersion = newVersion != currentVersion

        if isNewVersion || shouldProcessConfig(currentConfig) {
            let config = JsonToRemoteConfigModelMapper.mapJson(
                remoteMessagingConfig: jsonRemoteMessagingConfig,
                surveyActionMapper: remoteMessagingConfigMatcher.surveyActionMapper
            )
            let message = remoteMessagingConfigMatcher.evaluate(remoteConfig: config)
            Logger.remoteMessaging.debug("Message to present next: \(message.debugDescription, privacy: .public)")

            return ProcessorResult(version: jsonRemoteMessagingConfig.version, message: message)
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
