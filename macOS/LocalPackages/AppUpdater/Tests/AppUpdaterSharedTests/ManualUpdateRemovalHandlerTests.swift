//
//  ManualUpdateRemovalHandlerTests.swift
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
import AppUpdaterTestHelpers
import FeatureFlags
import Persistence
import PersistenceTestingUtils
import PrivacyConfig
import XCTest

final class ManualUpdateRemovalHandlerTests: XCTestCase {

    var settings: (any ThrowingKeyedStoring<UpdateControllerSettings>)!
    var mockFeatureFlagger: MockFeatureFlagger!
    var handler: ManualUpdateRemovalHandler!

    override func setUp() {
        super.setUp()
        settings = InMemoryThrowingKeyValueStore().throwingKeyedStoring()
        mockFeatureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        handler = nil
        mockFeatureFlagger = nil
        settings = nil
        super.tearDown()
    }

    private func makeHandler() {
        handler = ManualUpdateRemovalHandler(settings: settings, featureFlagger: mockFeatureFlagger)
    }

    // MARK: - State matrix tests

    func testNewUser_flagOn_shouldHide() throws {
        try settings.set(123, for: \.installBuild)
        mockFeatureFlagger.featuresStub[FeatureFlag.automaticUpdatesOnly.rawValue] = true
        makeHandler()

        XCTAssertTrue(handler.userNeverHadManualUpdateOption)
        XCTAssertTrue(handler.shouldHideManualUpdateOption)
    }

    func testNewUser_flagOff_shouldHide() throws {
        try settings.set(123, for: \.installBuild)
        mockFeatureFlagger.featuresStub[FeatureFlag.automaticUpdatesOnly.rawValue] = false
        makeHandler()

        XCTAssertTrue(handler.userNeverHadManualUpdateOption)
        XCTAssertTrue(handler.shouldHideManualUpdateOption)
    }

    func testLegacyUser_flagOn_shouldHide() {
        // installBuild not set — user previously had the manual option
        mockFeatureFlagger.featuresStub[FeatureFlag.automaticUpdatesOnly.rawValue] = true
        makeHandler()

        XCTAssertFalse(handler.userNeverHadManualUpdateOption)
        XCTAssertTrue(handler.shouldHideManualUpdateOption)
    }

    func testLegacyUser_flagOff_shouldNotHide() {
        // installBuild not set — user previously had the manual option
        mockFeatureFlagger.featuresStub[FeatureFlag.automaticUpdatesOnly.rawValue] = false
        makeHandler()

        XCTAssertFalse(handler.userNeverHadManualUpdateOption)
        XCTAssertFalse(handler.shouldHideManualUpdateOption)
    }
}
