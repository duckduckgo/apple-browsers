//
//  RemoteMessagingConfigMatcherProviderTest.swift
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
import Foundation
import Persistence
import CoreData
import Bookmarks
import Core

@testable import RemoteMessaging
@testable import DuckDuckGo

final class RemoteMessagingConfigMatcherProviderTest: XCTestCase {
    var remoteMessagingConfigMatcherProvider: RemoteMessagingConfigMatcherProvider!
    var themeManager: MockThemeManager!
    var featureFlagger: MockFeatureFlagger!

    override func setUp() {

        themeManager = MockThemeManager()
        featureFlagger = MockFeatureFlagger()

        let bookmarksDB = CoreDataDatabase.bookmarksMock

        remoteMessagingConfigMatcherProvider = RemoteMessagingConfigMatcherProvider(
            bookmarksDatabase: bookmarksDB,
            appSettings: AppSettingsMock(),
            internalUserDecider: MockInternalUserDecider(),
            duckPlayerStorage: MockDuckPlayerStorage(),
            featureFlagger: featureFlagger,
            themeManager: themeManager)
    }

    func testMatchesFeatureFlagAttributeForVisualUpdatesWhenEnabledInThemeManager() async {
        themeManager.properties = .init(isExperimentalThemingEnabled: true)
        featureFlagger.enabledFeatureFlags = []

        let matcher = await remoteMessagingConfigMatcherProvider.refreshConfigMatcher(using: EmptyRemoteMessagingStore())
        let matchingArray = AllFeatureFlagsEnabledMatchingAttribute(value: ["visualUpdates"])
        let result = matcher.evaluateAttribute(matchingAttribute: matchingArray)

        XCTAssertEqual(result, .match)
    }

    func testFailsMatchOfFeatureFlagAttributeForVisualUpdatesWhenDisabledInThemeManager() async {
        themeManager.properties = .init(isExperimentalThemingEnabled: false)
        featureFlagger.enabledFeatureFlags = [.visualUpdates]

        let matcher = await remoteMessagingConfigMatcherProvider.refreshConfigMatcher(using: EmptyRemoteMessagingStore())
        let matchingArray = AllFeatureFlagsEnabledMatchingAttribute(value: ["visualUpdates"])
        let result = matcher.evaluateAttribute(matchingAttribute: matchingArray)

        XCTAssertEqual(result, .fail)
    }

    override func tearDown() {
        remoteMessagingConfigMatcherProvider = nil
    }

    private func setUpValidBookmarksDatabase() -> CoreDataDatabase? {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return nil
        }
        return CoreDataDatabase(name: type(of: self).description(),
                                containerLocation: location,
                                model: model)
    }
}

private class EmptyRemoteMessagingStore: RemoteMessagingStoring {
    func saveProcessedResult(_ processorResult: RemoteMessaging.RemoteMessagingConfigProcessor.ProcessorResult) async { }
    func fetchRemoteMessagingConfig() -> RemoteMessaging.RemoteMessagingConfig? { nil }
    func fetchScheduledRemoteMessage() -> RemoteMessaging.RemoteMessageModel? { nil }
    func hasShownRemoteMessage(withID id: String) -> Bool { true }
    func fetchShownRemoteMessageIDs() -> [String] { [] }
    func dismissRemoteMessage(withID id: String) async { }
    func fetchDismissedRemoteMessageIDs() -> [String] { [] }
    func updateRemoteMessage(withID id: String, asShown shown: Bool) async { }
    func resetRemoteMessages() async { }
}
