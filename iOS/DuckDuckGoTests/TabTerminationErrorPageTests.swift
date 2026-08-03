//
//  TabTerminationErrorPageTests.swift
//  DuckDuckGoTests
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

import Core
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabTerminationErrorPageTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)

    func testWhenSettingsAreConfiguredThenValuesAreRead() {
        let settings = makeSettings(json: "{\"terminationCount\": 5, \"timeWindowSeconds\": 30}")

        XCTAssertEqual(settings.terminationCount, 5)
        XCTAssertEqual(settings.timeWindow, 30)
    }

    func testWhenSettingsAreMissingThenDefaultsAreUsed() {
        let settings = makeSettings(json: nil)

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 60)
    }

    func testWhenSettingsAreMalformedThenDefaultsAreUsed() {
        let settings = makeSettings(json: "not json")

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 60)
    }

    func testWhenIndividualSettingsAreInvalidThenEachFallsBackIndependently() {
        let settings = makeSettings(json: "{\"terminationCount\": -1, \"timeWindowSeconds\": 30}")

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 30)
    }

    func testWhenSettingsHaveWrongTypesThenDefaultsAreUsed() {
        let settings = makeSettings(json: "{\"terminationCount\": true, \"timeWindowSeconds\": \"30\"}")

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 60)
    }

    func testWhenFeatureIsDisabledThenErrorPageIsNotShown() {
        let detector = makeDetector(featureEnabled: false)

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
    }

    func testWhenThresholdIsReachedWithinWindowThenErrorPageIsShown() {
        let detector = makeDetector()

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
        date.addTimeInterval(30)
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
        date.addTimeInterval(30)
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "tab"))
    }

    func testWhenTerminationFallsOutsideWindowThenItIsPruned() {
        let detector = makeDetector()

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
        date.addTimeInterval(61)
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
    }

    func testWhenDifferentTabsTerminateThenHistoriesRemainIndependent() {
        let detector = makeDetector()

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "first"))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "first"))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "second"))
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "first"))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "second"))
    }

    func testWhenHistoryIsRemovedThenTabStartsFresh() {
        let detector = makeDetector()
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))

        detector.removeHistory(forTabID: "tab")

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab"))
    }

    func testPixelNames() {
        XCTAssertEqual(Pixel.Event.webViewWebKitTerminationErrorPageShown.name,
                       "m_webview_webkit-termination_error-page_shown")
        XCTAssertEqual(Pixel.Event.webViewWebKitTerminationErrorPageReload.name,
                       "m_webview_webkit-termination_error-page_reload")
        XCTAssertEqual(Pixel.Event.webViewWebKitTerminationErrorPageSendFeedback.name,
                       "m_webview_webkit-termination_error-page_send-feedback")
    }

    private func makeSettings(json: String?) -> TabTerminationErrorPageSettings {
        let configuration = MockPrivacyConfiguration()
        configuration.subfeatureSettings = json
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = configuration
        return TabTerminationErrorPageSettings(privacyConfigurationManager: manager)
    }

    private func makeDetector(featureEnabled: Bool = true,
                              json: String? = nil) -> TabTerminationErrorPageDetector {
        let configuration = MockPrivacyConfiguration()
        configuration.subfeatureSettings = json
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = configuration
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: featureEnabled ? [.tabTerminationErrorPage] : [])
        return TabTerminationErrorPageDetector(
            featureFlagger: featureFlagger,
            privacyConfigurationManager: manager,
            date: { self.date })
    }
}
