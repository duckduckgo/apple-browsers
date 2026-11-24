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

import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabTerminationErrorPageTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)
    private let page = URL(string: "https://example.com/page?id=1")!

    func testWhenSettingsAreConfiguredThenValuesAreRead() {
        let settings = makeSettings(
            json: "{\"terminationCount\": 5, \"timeWindowSeconds\": 30, \"supportedFormFactors\": [\"phone\"], \"matchPage\": false}")

        XCTAssertEqual(settings.terminationCount, 5)
        XCTAssertEqual(settings.timeWindow, 30)
        XCTAssertEqual(settings.supportedFormFactors, [.phone])
        XCTAssertFalse(settings.matchesPage)
    }

    func testWhenSettingsAreMissingThenDefaultsAreUsed() {
        let settings = makeSettings(json: nil)

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 60)
        XCTAssertEqual(settings.supportedFormFactors, [.phone, .tablet])
        XCTAssertTrue(settings.matchesPage)
    }

    func testWhenSettingsAreMalformedThenDefaultsAreUsed() {
        let settings = makeSettings(json: "not json")

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 60)
        XCTAssertEqual(settings.supportedFormFactors, [.phone, .tablet])
    }

    func testWhenIndividualSettingsAreInvalidThenEachFallsBackIndependently() {
        let settings = makeSettings(json: "{\"terminationCount\": -1, \"timeWindowSeconds\": 30}")

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 30)
    }

    func testWhenSettingsHaveWrongTypesThenDefaultsAreUsed() {
        let settings = makeSettings(
            json: "{\"terminationCount\": true, \"timeWindowSeconds\": \"30\", \"supportedFormFactors\": \"phone\", \"matchPage\": 0}")

        XCTAssertEqual(settings.terminationCount, 3)
        XCTAssertEqual(settings.timeWindow, 60)
        XCTAssertEqual(settings.supportedFormFactors, [.phone, .tablet])
        XCTAssertTrue(settings.matchesPage)
    }

    func testWhenFormFactorIsSupportedThenErrorPageIsShown() {
        let json = "{\"terminationCount\": 1, \"supportedFormFactors\": [\"tablet\"]}"
        XCTAssertEqual(makeSettings(json: json).supportedFormFactors, [.tablet])
        let detector = makeDetector(
            terminationCount: 1,
            supportedFormFactors: [.tablet],
            formFactor: .tablet)

        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "tab", url: page))
    }

    func testWhenFormFactorIsNotSupportedThenErrorPageIsNotShown() {
        let detector = makeDetector(
            terminationCount: 1,
            supportedFormFactors: [.phone],
            formFactor: .tablet)

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
    }

    func testWhenThresholdIsReachedWithinWindowThenErrorPageIsShown() {
        let detector = makeDetector()

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        date.addTimeInterval(30)
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        date.addTimeInterval(30)
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "tab", url: page))
    }

    func testWhenTerminationFallsOutsideWindowThenItIsPruned() {
        let detector = makeDetector()

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        date.addTimeInterval(61)
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
    }

    func testWhenDifferentTabsTerminateThenHistoriesRemainIndependent() {
        let detector = makeDetector()

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "first", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "first", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "second", url: page))
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "first", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "second", url: page))
    }

    func testWhenHistoryIsRemovedThenTabStartsFresh() {
        let detector = makeDetector()
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))

        detector.removeHistory(forTabID: "tab")

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
    }

    func testWhenTabNavigatesToAnotherPageThenCountStartsOver() {
        let detector = makeDetector(terminationCount: 2)
        let otherPage = URL(string: "https://example.com/other")!

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: otherPage))
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "tab", url: otherPage))
    }

    func testWhenTabReturnsToEarlierPageThenEarlierTerminationsAreNotCounted() {
        let detector = makeDetector(terminationCount: 2)
        let otherPage = URL(string: "https://example.com/other")!

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: otherPage))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
    }

    func testWhenQueryDiffersThenPagesAreDifferent() {
        let detector = makeDetector(terminationCount: 2)
        let otherQuery = URL(string: "https://example.com/page?id=2")!

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: otherQuery))
    }

    func testWhenOnlyFragmentDiffersThenPageIsTheSame() {
        let detector = makeDetector(terminationCount: 2)
        let fragment = URL(string: "https://example.com/page?id=1#section")!

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "tab", url: fragment))
    }

    func testWhenPageMatchingIsOffThenTerminationsOnDifferentPagesAreCountedTogether() {
        let detector = makeDetector(terminationCount: 2, matchesPage: false)
        let otherPage = URL(string: "https://example.com/other")!

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: page))
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "tab", url: otherPage))
    }

    func testWhenURLIsMissingThenTerminationsAreCountedTogether() {
        let detector = makeDetector(terminationCount: 2)

        XCTAssertFalse(detector.shouldShowErrorPage(forTabID: "tab", url: nil))
        XCTAssertTrue(detector.shouldShowErrorPage(forTabID: "tab", url: nil))
    }

    func testPixelNames() {
        XCTAssertEqual(TabTerminationErrorPagePixel.shown.name, "tab-termination_error-page_shown")
        XCTAssertEqual(TabTerminationErrorPagePixel.reload.name, "tab-termination_error-page_reload")
        XCTAssertEqual(TabTerminationErrorPagePixel.sendFeedback.name, "tab-termination_error-page_send-feedback")
    }

    func testInstrumentationFiresPixelKitEvents() {
        let pixelFiring = MockTabTerminationErrorPagePixelFiring()
        let instrumentation = DefaultTabTerminationErrorPageInstrumentation(pixelFiring: pixelFiring)

        instrumentation.errorPageShown()
        instrumentation.reloadSelected()
        instrumentation.sendFeedbackSelected()

        XCTAssertEqual(pixelFiring.calls.map(\.event.name), [
            "tab-termination_error-page_shown",
            "tab-termination_error-page_reload",
            "tab-termination_error-page_send-feedback"
        ])
        XCTAssertTrue(pixelFiring.calls.allSatisfy { $0.frequency == .dailyAndCount })
    }

    private func makeSettings(json: String?) -> TabTerminationErrorPageSettings {
        let configuration = MockPrivacyConfiguration()
        configuration.subfeatureSettings = json
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = configuration
        return TabTerminationErrorPageSettings(privacyConfigurationManager: manager)
    }

    private func makeDetector(terminationCount: Int = 3,
                              timeWindow: TimeInterval = 60,
                              supportedFormFactors: Set<TabTerminationErrorPageSettings.FormFactor> = [.phone, .tablet],
                              formFactor: TabTerminationErrorPageSettings.FormFactor = .phone,
                              matchesPage: Bool = true) -> TabTerminationErrorPageDetector {
        return TabTerminationErrorPageDetector(
            settings: MockTabTerminationErrorPageSettings(
                terminationCount: terminationCount,
                timeWindow: timeWindow,
                supportedFormFactors: supportedFormFactors,
                matchesPage: matchesPage),
            formFactor: formFactor,
            date: { self.date })
    }
}

private struct MockTabTerminationErrorPageSettings: TabTerminationErrorPageSettingsProviding {
    let terminationCount: Int
    let timeWindow: TimeInterval
    let supportedFormFactors: Set<TabTerminationErrorPageSettings.FormFactor>
    let matchesPage: Bool
}

private final class MockTabTerminationErrorPagePixelFiring: PixelFiring {

    struct Call {
        let event: PixelKit.Event
        let frequency: PixelKit.Frequency
    }

    private(set) var calls: [Call] = []

    func fire(event: PixelKit.Event,
              frequency: PixelKit.Frequency,
              options: PixelKit.Options,
              onComplete: @escaping PixelKit.CompletionBlock) {
        calls.append(.init(event: event, frequency: frequency))
        onComplete(true, nil)
    }
}
