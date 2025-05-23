//
//  RemoteMessagingConfigFetcher.swift
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

import Configuration
import Foundation
import Networking
import OSLog

/**
 * This protocol defines API for fetching RMF config from the server
 */
public protocol RemoteMessagingConfigFetching {
    func fetchRemoteMessagingConfig() async throws -> RemoteMessageResponse.JsonRemoteMessagingConfig
}

public struct RemoteMessagingConfigFetcher: RemoteMessagingConfigFetching {

    public let configurationFetcher: ConfigurationFetcher
    public let configurationStore: ConfigurationStoring

    public init(configurationFetcher: ConfigurationFetcher, configurationStore: ConfigurationStoring) {
        self.configurationFetcher = configurationFetcher
        self.configurationStore = configurationStore
    }

    public func fetchRemoteMessagingConfig() async throws -> RemoteMessageResponse.JsonRemoteMessagingConfig {
        let isDebug: Bool = {
#if DEBUG
            true
#else
            false
#endif
        }()
        do {
            try await configurationFetcher.fetch(.remoteMessagingConfig, isDebug: isDebug)
        } catch APIRequest.Error.invalidStatusCode(304) {}

        guard let responseData = configurationStore.loadData(for: .remoteMessagingConfig) else {
            throw RemoteMessageResponse.StatusError.noData
        }

        do {
            return try JSONDecoder().decode(RemoteMessageResponse.JsonRemoteMessagingConfig.self, from: responseData)
        } catch {
            Logger.remoteMessaging.error("PARSING ERROR: \(error)")
            throw RemoteMessageResponse.StatusError.parsingFailed
        }
    }
}
