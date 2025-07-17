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

/// Handles startup logic for setting and maintaining the default Safari user agent.
struct UserAgentConfiguration {

    enum Constants {

        static let userAgentCacheKey = "default_user_agent"

    }

    let userAgentManager: UserAgentManaging
    let store: ThrowingKeyValueStoring
    let osVersionProvider: OSVersionProviding
    let launchTaskManager: LaunchTaskManaging

    init(userAgentManager: UserAgentManaging = DefaultUserAgentManager.shared,
         store: ThrowingKeyValueStoring,
         osVersionProvider: OSVersionProviding = AppVersion.shared,
         launchTaskManager: LaunchTaskManaging) {
        self.userAgentManager = userAgentManager
        self.store = store
        self.osVersionProvider = osVersionProvider
        self.launchTaskManager = launchTaskManager
    }

    /// Configures the default user agent at app startup.
    ///
    /// If a cached user agent is found, it's used immediately without blocking.
    /// If the OS version has changed since the last retrieval, a background `LaunchTask` is registered
    /// to update the user agent.
    ///
    /// If no cached value exists (e.g., first launch), the user agent is retrieved "synchronously" and cached.
    ///
    /// - Parameter completion: Called when initial configuration completes (immediately if cached, or after async setup).
    /// Used primarily for tests.
    ///
    /// For more detail, see the https://app.asana.com/1/137249556945/project/1201392122292466/task/1210787475496146?focus=true.
    @MainActor
    func configure(completion: (() -> Void)? = nil) {
        if let cachedUserAgent {
            userAgentManager.setDefaultUserAgent(cachedUserAgent.userAgent)
            scheduleUserAgentUpdateIfNeeded(for: cachedUserAgent)
            completion?()
        } else {
            Task {
                await extractAndSetDefaultUserAgent()
                completion?()
            }
        }
    }

    private func scheduleUserAgentUpdateIfNeeded(for cached: CachedUserAgent) {
        guard osVersionProvider.osVersion != cached.osVersion else { return }
        launchTaskManager.register(task: BlockLaunchTask(name: "Update User Agent") { taskContext in
            Task {
                await extractAndSetDefaultUserAgent()
                taskContext.finish()
            }
        })
    }

    private var cachedUserAgent: CachedUserAgent? {
        if let data = try? store.object(forKey: Constants.userAgentCacheKey) as? Data {
            return try? PropertyListDecoder().decode(CachedUserAgent.self, from: data)
        }
        return nil
    }

    @MainActor
    private func extractAndSetDefaultUserAgent() async {
        if let userAgent = try? await userAgentManager.extractAndSetDefaultUserAgent() {
            cacheUserAgent(userAgent)
        }
    }

    private func cacheUserAgent(_ userAgent: String) {
        let userAgent = CachedUserAgent(userAgent: userAgent, osVersion: osVersionProvider.osVersion)
        let encodedUserAgent = try? PropertyListEncoder().encode(userAgent)
        try? store.set(encodedUserAgent, forKey: Constants.userAgentCacheKey)
    }

}
