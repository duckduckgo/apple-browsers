//
//  AboutPreferencesManualUpdateTests.swift
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

import AppUpdaterShared
import FeatureFlags
import PersistenceTestingUtils
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

private final class MockManualUpdateRemovalHandler: ManualUpdateRemovalHandling {
    var userNeverHadManualUpdateOption: Bool = false
    var shouldHideManualUpdateOption: Bool = false
}

@MainActor
final class AboutPreferencesManualUpdateTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockHandler: MockManualUpdateRemovalHandler!
    private var aboutPreferences: AboutPreferences!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockHandler = MockManualUpdateRemovalHandler()
    }

    override func tearDown() {
        aboutPreferences = nil
        mockHandler = nil
        mockFeatureFlagger = nil
        super.tearDown()
    }

    private func makeAboutPreferences() {
        aboutPreferences = AboutPreferences(
            internalUserDecider: mockFeatureFlagger.internalUserDecider,
            featureFlagger: mockFeatureFlagger,
            manualUpdateRemovalHandler: mockHandler,
            windowControllersManager: WindowControllersManagerMock(),
            keyValueStore: InMemoryThrowingKeyValueStore()
        )
    }

    // MARK: - shouldHideManualUpdateOption delegation

    func testShouldHide_delegatesToHandler_true() {
        mockHandler.shouldHideManualUpdateOption = true
        makeAboutPreferences()

        XCTAssertTrue(aboutPreferences.shouldHideManualUpdateOption)
    }

    func testShouldHide_delegatesToHandler_false() {
        mockHandler.shouldHideManualUpdateOption = false
        makeAboutPreferences()

        XCTAssertFalse(aboutPreferences.shouldHideManualUpdateOption)
    }

}
