//
//  UserAgentConfiguration.swift
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

import Core
import Persistence
import Common

struct CachedUserAgent: Codable {

    let userAgent: String
    let osVersion: String

}

struct UserAgentConfiguration {

    enum Constants {

        static let userAgentCacheKey = "default_user_agent"

    }

    let userAgentManager: UserAgentManager = DefaultUserAgentManager.shared
    let keyValueStore: ThrowingKeyValueStoring
    let appVersion: AppVersion = .shared
    let launchTaskManager: LaunchTaskManager

    @MainActor
    func configure() {
        if let cachedUserAgent {
            userAgentManager.setDefaultUserAgent(cachedUserAgent.userAgent)
            if appVersion.osVersion != cachedUserAgent.osVersion {
                launchTaskManager.register(task: BlockLaunchTask(name: "Update User Agent", onRun: { taskContext in
                    Task {
                        await extractAndSetDefaultUserAgent()
                        taskContext.finish()
                    }
                }))
            }
        } else {
            Task {
                await extractAndSetDefaultUserAgent()
            }
        }
    }

    private var cachedUserAgent: CachedUserAgent? {
        if let data = try? keyValueStore.object(forKey: "default_user_agent") as? Data {
            return try? PropertyListDecoder().decode(CachedUserAgent.self, from: data)
        }
        return nil
    }

    @MainActor
    public func extractAndSetDefaultUserAgent() async {
        if let userAgent = try? await userAgentManager.extractAndSetDefaultUserAgent() {
            cacheUserAgent(userAgent)
        }
    }

    private func cacheUserAgent(_ userAgent: String) {
        let userAgent = CachedUserAgent(userAgent: userAgent, osVersion: appVersion.osVersion)
        let encoded = try? PropertyListEncoder().encode(userAgent)
        try? keyValueStore.set(encoded, forKey: Constants.userAgentCacheKey)
    }

}
