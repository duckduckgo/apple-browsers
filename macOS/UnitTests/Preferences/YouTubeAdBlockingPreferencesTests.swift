//
//  YouTubeAdBlockingPreferencesTests.swift
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

import BrowserServicesKit
import Combine
import FeatureFlags
import Persistence
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import WebExtensions
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class YouTubeAdBlockingPreferencesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var sut: YouTubeAdBlockingPreferences!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "\(type(of: self))")!
        defaults.removePersistentDomain(forName: "\(type(of: self))")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "\(type(of: self))")
        defaults = nil
        sut = nil
        super.tearDown()
    }

    private func makeSUT(pixelFiring: PixelFiring? = nil) -> YouTubeAdBlockingPreferences {
        YouTubeAdBlockingPreferences(
            settings: defaults.keyedStoring(),
            pixelFiring: pixelFiring
        )
    }

    private func makeSUT(
        adBlockingAvailability: AdBlockingAvailabilityProviding,
        featureFlagger: FeatureFlagger
    ) -> YouTubeAdBlockingPreferences {
        YouTubeAdBlockingPreferences(
            settings: defaults.keyedStoring(),
            adBlockingAvailability: adBlockingAvailability,
            featureFlagger: featureFlagger
        )
    }

    private func storage() -> any KeyedStoring<YouTubeAdBlockingSettings> {
        defaults.keyedStoring()
    }

    private func drainMainQueue() {
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Pixel Firing

    func testWhenEnablingAdBlockingThenEnabledPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionEnabled, frequency: .dailyAndCount)
        ])
        sut = makeSUT(pixelFiring: pixelMock)

        sut.youTubeAdBlockingEnabled = true

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    func testWhenDisablingAdBlockingThenDisabledPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionEnabled, frequency: .dailyAndCount),
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionDisabled, frequency: .dailyAndCount)
        ])
        sut = makeSUT(pixelFiring: pixelMock)

        sut.youTubeAdBlockingEnabled = true
        sut.youTubeAdBlockingEnabled = false

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    func testWhenSettingSameValueThenNoPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionEnabled, frequency: .dailyAndCount)
        ])
        sut = makeSUT(pixelFiring: pixelMock)

        sut.youTubeAdBlockingEnabled = true
        sut.youTubeAdBlockingEnabled = true

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    func testWhenNoPixelFiringInjectedThenNoPixelIsFired() {
        sut = makeSUT(pixelFiring: nil)

        sut.youTubeAdBlockingEnabled = true
        sut.youTubeAdBlockingEnabled = false
    }

    // MARK: - Rollout-aware default

    func testWhenStorageIsNilAndRolloutOffThenCachedEnabledIsFalse() {
        let availability = TestAdBlockingAvailability()
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: MockFeatureFlagger())

        XCTAssertFalse(sut.youTubeAdBlockingEnabled)
    }

    func testWhenStorageIsNilAndRolloutOnThenCachedEnabledIsTrue() {
        let availability = TestAdBlockingAvailability()
        availability.areAdBlockingDefaultsActive = true
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: MockFeatureFlagger())

        XCTAssertTrue(sut.youTubeAdBlockingEnabled)
    }

    func testWhenStorageIsExplicitTrueThenRolloutDefaultIsIgnored() {
        var settings = storage()
        settings.youTubeAdBlockingEnabled = true
        let availability = TestAdBlockingAvailability()  // rollout off
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: MockFeatureFlagger())

        XCTAssertTrue(sut.youTubeAdBlockingEnabled)
    }

    func testWhenStorageIsExplicitFalseThenRolloutDefaultIsIgnored() {
        var settings = storage()
        settings.youTubeAdBlockingEnabled = false
        let availability = TestAdBlockingAvailability()
        availability.areAdBlockingDefaultsActive = true  // rollout on
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: MockFeatureFlagger())

        XCTAssertFalse(sut.youTubeAdBlockingEnabled)
    }

    // MARK: - markDisclosureHiddenIfExistingUser

    func testMarkDisclosureWithNilStorageAndRolloutOffPinsToFalse() {
        let availability = TestAdBlockingAvailability()
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: MockFeatureFlagger())

        sut.markDisclosureHiddenIfExistingUser()

        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, false)
        XCTAssertFalse(sut.isDisclosureHidden)
    }

    func testMarkDisclosureWithNilStorageAndRolloutOnPinsToTrue() {
        let availability = TestAdBlockingAvailability()
        availability.areAdBlockingDefaultsActive = true
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: MockFeatureFlagger())

        sut.markDisclosureHiddenIfExistingUser()

        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, true)
        XCTAssertTrue(sut.isDisclosureHidden)
    }

    func testMarkDisclosureWithExplicitTrueStorageFirstTimePinsToTrue() {
        var settings = storage()
        settings.youTubeAdBlockingEnabled = true
        sut = makeSUT(adBlockingAvailability: TestAdBlockingAvailability(), featureFlagger: MockFeatureFlagger())

        sut.markDisclosureHiddenIfExistingUser()

        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, true)
        XCTAssertTrue(sut.isDisclosureHidden)
    }

    func testMarkDisclosureWithExplicitFalseStorageFirstTimePinsToFalse() {
        var settings = storage()
        settings.youTubeAdBlockingEnabled = false
        sut = makeSUT(adBlockingAvailability: TestAdBlockingAvailability(), featureFlagger: MockFeatureFlagger())

        sut.markDisclosureHiddenIfExistingUser()

        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, false)
        XCTAssertFalse(sut.isDisclosureHidden)
    }

    func testMarkDisclosureWithExplicitStoragePreservesExistingPin() {
        var settings = storage()
        settings.youTubeAdBlockingEnabled = true
        settings.shouldHideYouTubeAdBlockingDisclosure = false  // pre-existing pin
        sut = makeSUT(adBlockingAvailability: TestAdBlockingAvailability(), featureFlagger: MockFeatureFlagger())

        sut.markDisclosureHiddenIfExistingUser()

        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, false)
        XCTAssertFalse(sut.isDisclosureHidden)
    }

    func testMarkDisclosureWithNilStorageReEvaluatesAcrossRolloutFlip() {
        let availability = TestAdBlockingAvailability()
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: MockFeatureFlagger())

        // Rollout off → SHOWN
        sut.markDisclosureHiddenIfExistingUser()
        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, false)

        // Rollout on → re-pin to HIDDEN
        availability.areAdBlockingDefaultsActive = true
        sut.markDisclosureHiddenIfExistingUser()
        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, true)
    }

    // MARK: - Publisher-triggered re-evaluation

    func testPublisherTriggerSyncsDisclosureForNilStorage() {
        let availability = TestAdBlockingAvailability()
        let featureFlagger = MockFeatureFlagger()
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: featureFlagger)
        sut.markDisclosureHiddenIfExistingUser()
        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, false)

        availability.areAdBlockingDefaultsActive = true
        featureFlagger.triggerUpdate()
        drainMainQueue()

        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, true)
        XCTAssertTrue(sut.isDisclosureHidden)
        XCTAssertTrue(sut.youTubeAdBlockingEnabled)
    }

    func testPublisherTriggerDoesNotTouchExplicitStorageDisclosure() {
        var settings = storage()
        settings.youTubeAdBlockingEnabled = true
        settings.shouldHideYouTubeAdBlockingDisclosure = false  // pre-existing pin
        let availability = TestAdBlockingAvailability()
        let featureFlagger = MockFeatureFlagger()
        sut = makeSUT(adBlockingAvailability: availability, featureFlagger: featureFlagger)

        availability.areAdBlockingDefaultsActive = true
        featureFlagger.triggerUpdate()
        drainMainQueue()

        XCTAssertEqual(storage().shouldHideYouTubeAdBlockingDisclosure, false)
        XCTAssertFalse(sut.isDisclosureHidden)
    }
}

private final class TestAdBlockingAvailability: AdBlockingAvailabilityProviding {
    var isFeatureSupported: Bool = false
    var isEnabledByUser: Bool = false
    var areAdBlockingDefaultsActive: Bool = false
    func shouldShowAnimation(for url: URL) -> Bool { false }
}
