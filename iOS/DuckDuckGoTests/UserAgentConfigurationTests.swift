//
//  UserAgentConfigurationTests.swift
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

import XCTest
import Persistence
import PersistenceTestingUtils
import Common
import Testing
@testable import DuckDuckGo

@MainActor
final class UserAgentConfigurationTests {

    let uaManager = MockUserAgentManager(privacyConfig: MockPrivacyConfiguration())
    let taskManager = MockLaunchTaskManager()
    let store = MockKeyValueStore()

    @Test
    func testFirstLaunchExtractsAndSetsAndCachesDefaultUserAgent() async throws {
        let osProvider = MockOSVersionProvider(osVersionMajorMinorPatch: "18.0.1")

        let config = UserAgentConfiguration(
            userAgentManager: uaManager,
            store: store,
            osVersionProvider: osProvider,
            launchTaskManager: taskManager
        )

        await withCheckedContinuation { continuation in
            config.configure {
                continuation.resume()
            }
        }

        #expect(uaManager.extractAndSetDefaultUserAgentCallCount == 1)
        #expect(uaManager.extractedAndSetDefaultUserAgent == "mock-UA")

        let encodedData = try #require(store.store["default_user_agent"] as? Data)
        let decoded = try? PropertyListDecoder().decode(CachedUserAgent.self, from: encodedData)
        #expect(decoded?.userAgent == "mock-UA")
        #expect(decoded?.osVersion == "18.0.1")
    }

    @Test
    func testCachedLaunchWithSameOSSetsUserAgentAndNoLaunchTaskIsScheduled() async {
        let osProvider = MockOSVersionProvider(osVersionMajorMinorPatch: "18.0.1")
        let ua = CachedUserAgent(userAgent: "cached-UA", osVersion: "18.0.1")
        let encoded = try? PropertyListEncoder().encode(ua)
        store.store["default_user_agent"] = encoded

        let config = UserAgentConfiguration(
            userAgentManager: uaManager,
            store: store,
            osVersionProvider: osProvider,
            launchTaskManager: taskManager
        )

        await withCheckedContinuation { continuation in
            config.configure {
                continuation.resume()
            }
        }

        #expect(uaManager.extractAndSetDefaultUserAgentCallCount == 0)
        #expect(uaManager.setUserAgentCalled == "cached-UA")
        #expect(taskManager.registeredTasks.isEmpty)
    }

    @Test
    func testCachedLaunchWithDifferentOSSetsUserAgentAndSchedulesUserAgentUpdateTask() async {
        let osProvider = MockOSVersionProvider(osVersionMajorMinorPatch: "18.0.2")
        let ua = CachedUserAgent(userAgent: "cached-UA", osVersion: "18.0.1")
        let encoded = try? PropertyListEncoder().encode(ua)
        store.store["default_user_agent"] = encoded

        let config = UserAgentConfiguration(
            userAgentManager: uaManager,
            store: store,
            osVersionProvider: osProvider,
            launchTaskManager: taskManager
        )

        await withCheckedContinuation { continuation in
            config.configure {
                continuation.resume()
            }
        }

        #expect(uaManager.extractAndSetDefaultUserAgentCallCount == 0)
        #expect(uaManager.setUserAgentCalled == "cached-UA")
        #expect(taskManager.registeredTasks.count == 1)
        #expect(taskManager.registeredTasks.contains(where: { $0.name == "Update User Agent" }))
    }


    final class MockLaunchTaskManager: LaunchTaskManaging {

        var registeredTasks: [LaunchTask] = []

        func register(task: LaunchTask) {
            registeredTasks.append(task)
        }

    }

    struct MockOSVersionProvider: OSVersionProviding {

        var osVersionMajorMinorPatch: String

    }

}
