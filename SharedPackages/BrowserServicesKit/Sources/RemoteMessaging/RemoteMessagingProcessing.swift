//
//  RemoteMessagingProcessing.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Common
import Configuration
import os.log

/**
 * This protocol defines API for providing RMF config matcher
 * that contains values of matched attributes that the config
 * file is evaluated against.
 *
 * Client apps should implement it and pass to a class implementing
 * RemoteMessagingProcessing.
 */
public protocol RemoteMessagingConfigMatcherProviding {
    func refreshConfigMatcher(using store: RemoteMessagingStoring) async -> RemoteMessagingConfigMatcher
}

/**
 * This protocol defines API for Remote Messaging client in the app.
 */
public protocol RemoteMessagingProcessing {
    /// Defines endpoint URL where the config file is available.
    var endpoint: URL { get }

    /// This holds the fetcher that downloads the config file from the server.
    var configFetcher: RemoteMessagingConfigFetching { get }

    /// This holds the config matcher provider that updates the config matcher before the config is evaluated.
    var configMatcherProvider: RemoteMessagingConfigMatcherProviding { get }

    /// Provides feature flag support for RMF.
    var remoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding { get }

    /**
     * This function returns a config processor.
     *
     * Config processor performs evaluation of the JSON config file against the matcher containing
     * app-specific, device-specific and user-specific matched attributes. Default implementation is provided.
     */
    func configProcessor(for configMatcher: RemoteMessagingConfigMatcher) -> RemoteMessagingConfigProcessing

    /**
     * This is the entry point to RMF from the client app.
     *
     * This function fetches the config, updates config matcher, evaluates the config against the matcher
     * and stores the result as needed. Client apps should call this function in order to refresh remote messages.
     * When messages are updated, `RemoteMessagingStore.Notifications.remoteMessagesDidChange` notification is posted.
     * Default implementation is provided.
     */
    func fetchAndProcess(using store: RemoteMessagingStoring) async throws
}

public extension RemoteMessagingProcessing {

    func configProcessor(for configMatcher: RemoteMessagingConfigMatcher) -> RemoteMessagingConfigProcessing {
        RemoteMessagingConfigProcessor(remoteMessagingConfigMatcher: configMatcher)
    }

    func fetchAndProcess(using store: RemoteMessagingStoring) async throws {
        guard remoteMessagingAvailabilityProvider.isRemoteMessagingAvailable else {
            Logger.remoteMessaging.debug("Remote messaging feature flag is disabled, skipping fetching messages")
            return
        }
        do {
            let jsonConfig = try await configFetcher.fetchRemoteMessagingConfig()
            Logger.remoteMessaging.debug("Successfully fetched remote messages")

            let remoteMessagingConfigMatcher = await configMatcherProvider.refreshConfigMatcher(using: store)

            let processor = configProcessor(for: remoteMessagingConfigMatcher)
            let storedConfig = store.fetchRemoteMessagingConfig()

            if let processorResult = processor.process(jsonRemoteMessagingConfig: jsonConfig, currentConfig: storedConfig) {
                await store.saveProcessedResult(processorResult)
            }

        } catch {
            Logger.remoteMessaging.error("Failed to fetch remote messages \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
