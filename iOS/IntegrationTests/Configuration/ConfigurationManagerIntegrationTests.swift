//
//  ConfigurationManagerIntegrationTests.swift
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
import Core
@testable import Configuration
@testable import DuckDuckGo

final class ConfigurationManagerIntegrationTests: XCTestCase {

    var configManager: ConfigurationManager!
    var customURLProvider: CustomConfigurationURLProviding!

    override func setUpWithError() throws {
        let internalUserDecider = MockInteranlUserDecider()
        internalUserDecider.isInternalUser = true
        customURLProvider = MockCustomURLProvider()
        let fetcher = ConfigurationFetcher(store: MockConfigurationStoring(), configurationURLProvider: customURLProvider)
        configManager = ConfigurationManager(fetcher: fetcher)
    }

    override func tearDownWithError() throws {
        customURLProvider = nil
        configManager = nil
    }

    // Test temporarily disabled due to failure
    func testTdsAreFetchedFromURLBasedOnPrivacyConfigExperiment() async {
        // GIVEN
        await configManager.fetchAndUpdateTrackerBlockingDependencies()
        let etag = ContentBlocking.shared.trackerDataManager.fetchedData?.etag
        // use test privacyConfiguration link with tds experiments
        customURLProvider.setCustomURL(URL(string: "https://staticcdn.duckduckgo.com/trackerblocking/config/test/macos-config.json"), for: .privacyConfiguration)

        // WHEN
        await configManager.fetchAndUpdateTrackerBlockingDependencies()

        // THEN
        let newEtag = ContentBlocking.shared.trackerDataManager.fetchedData?.etag
        XCTAssertNotEqual(etag, newEtag)
        XCTAssertEqual(newEtag, "\"5c0f8d8cdcd80e3f26889323dae1dff9\"")

        // RESET
        customURLProvider.setCustomURL(nil, for: .privacyConfiguration)
        await configManager.fetchAndUpdateTrackerBlockingDependencies()
        let resetEtag = ContentBlocking.shared.trackerDataManager.fetchedData?.etag
        XCTAssertNotEqual(newEtag, resetEtag)
    }

}
