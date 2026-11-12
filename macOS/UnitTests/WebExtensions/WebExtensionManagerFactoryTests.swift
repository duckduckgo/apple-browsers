//
//  WebExtensionManagerFactoryTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import EventHub
import FeatureFlags_macOS
import Persistence
import PrivacyConfig
import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class WebExtensionManagerFactoryTests: XCTestCase {
    func testUpdateDiscoveryFlagChangesApplyWithoutRecreatingManager() async throws {
        for enabled in [false, true] {
            let flags = MockFeatureFlagger(featuresStub: [FeatureFlag.webExtensionUpdateDiscovery.rawValue: enabled])
            let storage = try DiscoveryStateStorage()
            let manager = makeManager(storage: storage, flags: flags)
            let store = try XCTUnwrap(manager.chromeWebStore)
            if enabled {
                try await waitForCondition { store.canCheckForUpdates }
            }
            XCTAssertEqual(store.canCheckForUpdates, enabled)
            XCTAssertEqual(storage.discoveryReads, 1, "The same coordinator restores timing once, even when initially disabled")

            flags.featuresStub[FeatureFlag.webExtensionUpdateDiscovery.rawValue] = !enabled
            flags.triggerUpdate()
            if !enabled {
                try await waitForCondition { store.canCheckForUpdates }
            }
            XCTAssertEqual(store.canCheckForUpdates, !enabled)
            await store.checkForUpdatesNow()
            XCTAssertEqual(storage.discoveryReads, 1, "Toggling the flag must retain the coordinator and its timing state")

            flags.featuresStub[FeatureFlag.webExtensionUpdateDiscovery.rawValue] = enabled
            flags.triggerUpdate()
            if enabled {
                try await waitForCondition { store.canCheckForUpdates }
            }
            await store.checkForUpdatesNow()
            XCTAssertEqual(store.canCheckForUpdates, enabled)
            XCTAssertEqual(storage.discoveryReads, 1)
            withExtendedLifetime(manager) {}
        }
    }

    func testAppStoreBuildDoesNotStartUpdateDiscoveryWhenFlagIsOn() async throws {
        let flags = MockFeatureFlagger(featuresStub: [FeatureFlag.webExtensionUpdateDiscovery.rawValue: true])
        let storage = try DiscoveryStateStorage()
        let manager = makeManager(storage: storage, flags: flags, isAppStore: true)
        let store = try XCTUnwrap(manager.chromeWebStore)
        XCTAssertFalse(store.canCheckForUpdates)
        await store.checkForUpdatesNow()
        flags.featuresStub[FeatureFlag.webExtensionUpdateDiscovery.rawValue] = false
        flags.triggerUpdate()
        flags.featuresStub[FeatureFlag.webExtensionUpdateDiscovery.rawValue] = true
        flags.triggerUpdate()
        await store.checkForUpdatesNow()
        XCTAssertFalse(store.canCheckForUpdates)
        XCTAssertEqual(storage.discoveryReads, 0)
    }

    private func waitForCondition(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Condition was not met before the timeout", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeManager(storage: DiscoveryStateStorage, flags: MockFeatureFlagger, isAppStore: Bool = false) -> WebExtensionManager {
        let buildType = ApplicationBuildTypeMock()
        buildType.isAppStoreBuild = isAppStore
        buildType.isSparkleBuild = !isAppStore
        return WebExtensionManagerFactory.makeManager(keyValueStore: storage,
                                                     privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                     autoconsentPreferences: Preferences(),
                                                     themeManager: ThemeManager(appearancePreferences: .mock),
                                                     buildType: buildType, featureFlagger: flags,
                                                     eventHub: RecordingEventHub())
    }

    private struct Preferences: AutoconsentPreferencesProviding {
        var cookiePopupPreference: CookiePopupPreference { .off }
    }

    private final class DiscoveryStateStorage: ThrowingKeyValueStoring {
        private static let key = "web-extension-update-discovery"
        private var values: [String: Any] = [:]
        private(set) var discoveryReads = 0

        init() throws {
            // Every real check is deferred, so this integration test never contacts Google or reads installations.
            values[Self.key] = try JSONSerialization.data(withJSONObject: [
                "retryNotBefore": Date().addingTimeInterval(24 * 60 * 60).timeIntervalSinceReferenceDate
            ])
        }

        func object(forKey key: String) throws -> Any? {
            if key == Self.key { discoveryReads += 1 }
            return values[key]
        }

        func set(_ value: Any?, forKey key: String) throws {
            values[key] = value
        }

        func removeObject(forKey key: String) throws {
            values.removeValue(forKey: key)
        }
    }
}
