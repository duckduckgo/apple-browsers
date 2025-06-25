//
//  RemoteMessagingConfigMatcherProviderTests.swift
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

import Foundation
import XCTest
import BrowserServicesKit
import Persistence
import Bookmarks
import Subscription
import FeatureFlags
@testable import RemoteMessaging
@testable import DuckDuckGo_Privacy_Browser

final class RemoteMessagingConfigMatcherProviderTests: XCTestCase {
    // Test: Feature flag is on, but visualStyle.isNewStyle is false → should NOT return the message
    func testVisualUpdatesFeatureFlag_WhenFeatureFlagOnButVisualStyleNotNew_ShouldNotBeInEnabledFlags() async {
        // Given
        let featureFlagger = MockFeatureFlagger()
        let visualStyle: VisualStyleProviding = VisualStyle.legacy
        featureFlagger.enabledFeatureFlags = [FeatureFlag.visualUpdates]

        let remoteConfig = provideRemoteStoreWithVisualUpdateMessage()
        let provider = createProvider(featureFlagger: featureFlagger, visualStyle: visualStyle)

        // When
        let configMatcher = await provider.refreshConfigMatcher(using: MockRemoteMessagingStore())

        // Then
        XCTAssertNil(configMatcher.evaluate(remoteConfig: remoteConfig))
    }

    // Test: Feature flag is off → should NOT return the message
    func testVisualUpdatesFeatureFlag_WhenFeatureFlagOff_ShouldNotBeInEnabledFlags() async {
        // Given
        let featureFlagger = MockFeatureFlagger()
        let visualStyle: VisualStyleProviding = VisualStyle.legacy
        featureFlagger.enabledFeatureFlags = []

        let remoteConfig = provideRemoteStoreWithVisualUpdateMessage()
        let provider = createProvider(featureFlagger: featureFlagger, visualStyle: visualStyle)

        // When
        let configMatcher = await provider.refreshConfigMatcher(using: MockRemoteMessagingStore())

        // Then
        XCTAssertNil(configMatcher.evaluate(remoteConfig: remoteConfig))
    }

    // Test: Feature flag is on and visualStyle.isNewStyle is true → should return the message
    func testVisualUpdatesFeatureFlag_WhenFeatureFlagOnAndVisualStyleNew_ShouldBeInEnabledFlags() async {
        // Given
        let featureFlagger = MockFeatureFlagger()
        let visualStyle: VisualStyleProviding = VisualStyle.current
        featureFlagger.enabledFeatureFlags = [FeatureFlag.visualUpdates]

        let remoteConfig = provideRemoteStoreWithVisualUpdateMessage()
        let provider = createProvider(featureFlagger: featureFlagger, visualStyle: visualStyle)

        // When
        let configMatcher = await provider.refreshConfigMatcher(using: MockRemoteMessagingStore())

        // Then
        XCTAssertNotNil(configMatcher.evaluate(remoteConfig: remoteConfig))
    }

    // MARK: - Helper Methods

    private func provideRemoteStoreWithVisualUpdateMessage() -> RemoteConfigModel {
        let remoteMessage = RemoteMessageModel(id: "1",
                                               content: .bigSingleAction(titleText: "DuckDuckGo got a refresh!",
                                                                         descriptionText: "New icons, fresh styles, and the same world-class protection.",
                                                                         placeholder: .announce,
                                                                         primaryActionText: "Share Feedback",
                                                                         primaryAction: .navigation(value: .feedback)),
                                               matchingRules: [23],
                                               exclusionRules: [],
                                               isMetricsEnabled: false)
        let matchingAttributes: [MatchingAttribute] = [
            AppVersionMatchingAttribute(min: "1.143.0", fallback: false),
            AllFeatureFlagsEnabledMatchingAttribute(value: ["visualUpdates"])
        ]
        let remoteRuleModel = RemoteConfigRule(id: 23, targetPercentile: nil, attributes: matchingAttributes)

        return RemoteConfigModel(messages: [remoteMessage], rules: [remoteRuleModel])
    }

    private func createProvider(featureFlagger: FeatureFlagger, visualStyle: VisualStyleProviding) -> RemoteMessagingConfigMatcherProvider {
        let bookmarksDB = CoreDataDatabase.bookmarksMock
        return RemoteMessagingConfigMatcherProvider(
            bookmarksDatabase: bookmarksDB,
            appearancePreferences: .mock,
            startupPreferencesPersistor: StartupPreferencesPersistorMock(launchToCustomHomePage: false, customHomePageURL: ""),
            duckPlayerPreferencesPersistor: DuckPlayerPreferencesPersistorMock(),
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            internalUserDecider: MockInternalUserDecider(),
            statisticsStore: MockStatisticsStore(),
            variantManager: MockVariantManager(),
            subscriptionManager: DefaultSubscriptionManager(),
            featureFlagger: featureFlagger,
            visualStyle: visualStyle
        )
    }
}

// MARK: - Mocks

extension CoreDataDatabase {

    static func tempDBDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    static func mock(
        bundle: Bundle,
        modelName: String,
        dbName: String = "Test",
        containerLocation: URL = MockBookmarksDatabase.tempDBDir()
    ) -> CoreDataDatabase {
        let model = CoreDataDatabase.loadModel(from: bundle, named: modelName)!
        let db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        db.loadStore()
        return db
    }

}
extension CoreDataDatabase {

    static var bookmarksMock: CoreDataDatabase {
        mock(bundle: Bookmarks.bundle, modelName: "BookmarksModel")
    }

}
