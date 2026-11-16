//
//  SyncDataProvidersSourceTests.swift
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

import XCTest
import DDGSync
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class SyncDataProvidersSourceTests: XCTestCase {

    var temporaryDirectory: URL!
    var dataProvidersSource: SyncDataProvidersSource!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let model = try XCTUnwrap(CoreDataDatabase.loadModel(from: DDGSync.bundle, named: "SyncMetadata"))
        let bookmarksDatabase = CoreDataDatabase(name: "",
                                                 containerLocation: temporaryDirectory.appendingPathComponent("Bookmarks"),
                                                 model: model,
                                                 readOnly: true,
                                                 options: [:])

        // A regular file where the store directory should be makes the metadata store fail to load.
        let blockingFile = temporaryDirectory.appendingPathComponent("NotADirectory")
        try Data().write(to: blockingFile)
        let failingMetadataDatabase = SyncMetadataDatabase(db: SyncMetadataDatabase.make(location: blockingFile.appendingPathComponent("SyncMetadata")))

        let appearancePreferences = AppearancePreferences(persistor: MockAppearancePreferencesPersistor(),
                                                          privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                          featureFlagger: MockFeatureFlagger(),
                                                          aiChatMenuConfig: MockAIChatConfig())

        dataProvidersSource = SyncDataProvidersSource(
            bookmarksDatabase: bookmarksDatabase,
            bookmarkManager: MockBookmarkManager(),
            appearancePreferences: appearancePreferences,
            keyValueStore: MockThrowingKeyValueStore(),
            syncErrorHandler: SyncErrorHandler(),
            featureFlagger: MockFeatureFlagger(),
            syncMetadataDatabase: failingMetadataDatabase
        )
    }

    override func tearDownWithError() throws {
        dataProvidersSource = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testWhenMetadataStoreFailsToLoadThenNoDataProvidersAreReturned() {
        let providers = dataProvidersSource.makeDataProviders()

        XCTAssertTrue(providers.isEmpty)
        XCTAssertNil(dataProvidersSource.bookmarksAdapter.provider)
        XCTAssertNil(dataProvidersSource.credentialsAdapter.provider)
        XCTAssertNil(dataProvidersSource.settingsAdapter.provider)
    }

    func testWhenMetadataStoreFailsToLoadThenLaterCallsRetryWithoutCrashing() {
        XCTAssertTrue(dataProvidersSource.makeDataProviders().isEmpty)
        XCTAssertTrue(dataProvidersSource.makeDataProviders().isEmpty)
    }
}
