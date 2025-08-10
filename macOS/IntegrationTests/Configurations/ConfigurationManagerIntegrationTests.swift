//
//  ConfigurationManagerIntegrationTests.swift
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
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser
import Combine
import Persistence
@testable import Configuration
import PersistenceTestingUtils

final class ConfigurationManagerIntegrationTests: XCTestCase {

    var configManager: ConfigurationManager!
    var customURLProvider: ConfigurationURLProvider!

    override func setUpWithError() throws {
        customURLProvider = ConfigurationURLProvider(
            defaultProvider: AppConfigurationURLProvider(privacyConfigurationManager: MockPrivacyConfigurationManager(), featureFlagger: MockFeatureFlagger()), internalUserDecider: MockInternalUserDecider(), store: MockCustomConfigurationURLStore())
        let fetcher = ConfigurationFetcher(store: MockConfigurationStoring(), configurationURLProvider: customURLProvider)
        let privacyFeatures = Application.appDelegate.privacyFeatures
        configManager = ConfigurationManager(fetcher: fetcher,
                                             store: MockConfigurationStoring(),
                                             defaults: MockKeyValueStore(),
                                             trackerDataManager: privacyFeatures.contentBlocking.trackerDataManager,
                                             privacyConfigurationManager: privacyFeatures.contentBlocking.privacyConfigurationManager,
                                             contentBlockingManager: privacyFeatures.contentBlocking.contentBlockingManager,
                                             httpsUpgrade: privacyFeatures.httpsUpgrade)
    }

    override func tearDownWithError() throws {
        configManager = nil
        customURLProvider = nil
    }

    // Test temporarily disabled due to failure
    func testTdsAreFetchedFromURLBasedOnPrivacyConfigExperiment() async {
        // GIVEN
        await configManager.refreshNow()
        let etag = await Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager.fetchedData?.etag
        // use test privacyConfiguration link with tds experiments
        customURLProvider.setCustomURL(URL(string: "https://staticcdn.duckduckgo.com/trackerblocking/config/test/macos-config.json"), for: .privacyConfiguration)

        // WHEN
        await configManager.refreshNow()

        // THEN
        let newEtag = await Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager.fetchedData?.etag
        XCTAssertNotEqual(etag, newEtag)
        XCTAssertEqual(newEtag, "\"2ce60c57c3d384f986ccbe2c422aac44\"")

        // RESET
        customURLProvider.setCustomURL(nil, for: .privacyConfiguration)
        await configManager.refreshNow()
        let resetEtag = await Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager.fetchedData?.etag
        XCTAssertNotEqual(newEtag, resetEtag)
    }

}
