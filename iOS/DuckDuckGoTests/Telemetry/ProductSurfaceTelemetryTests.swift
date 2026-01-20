//
//  ProductSurfaceTelemetryTests.swift
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
@testable import Core

final class ProductSurfaceTelemetryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PixelFiringMock.tearDown()
    }

    override func tearDown() {
        PixelFiringMock.tearDown()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTelemetry(enabled: Bool) -> ProductSurfaceTelemetry {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: enabled ? [.productTelemeterySurfaceUsage] : [])
        return PixelProductSurfaceTelemetry(featureFlagger: flagger, dailyPixelFiring: PixelFiringMock.self)
    }

    // MARK: - Feature disabled

    func testWhenFeatureDisabled_NoPixelsAreFired() {
        let telemetry = makeTelemetry(enabled: false)

        telemetry.menuUsed()
        telemetry.dailyActiveUser()
        telemetry.iPadUsed(isPad: true)
        telemetry.landscapeModeUsed()
        telemetry.keyboardActive()
        telemetry.autocompleteUsed()
        telemetry.navigationCompleted(url: URL(string: "https://example.com"))
        telemetry.duckAIUsed()
        telemetry.tabManagerUsed()
        telemetry.dataClearingUsed()
        telemetry.newTabPageUsed()
        telemetry.settingsUsed()
        telemetry.bookmarksPageUsed()
        telemetry.passwordsPageUsed()

        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)
    }

    // MARK: - Individual events

    func testMenuUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.menuUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageMenu.name)
    }

    func testDailyActiveUser_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.dailyActiveUser()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageDAU.name)
    }

    func testIPadUsed_FiresOnlyWhenIsPadTrue() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.iPadUsed(isPad: false)
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)

        telemetry.iPadUsed(isPad: true)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageIPad.name)
    }

    func testLandscapeModeUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.landscapeModeUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageLandscapeMode.name)
    }

    func testKeyboardActive_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.keyboardActive()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageKeyboardActive.name)
    }

    func testAutocompleteUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.autocompleteUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageAutocomplete.name)
    }

    func testNavigationCompleted_WithNilURL_DoesNotFire() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.navigationCompleted(url: nil)
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)
    }

    func testNavigationCompleted_WithSearchURL_FiresSERPPixel() {
        let telemetry = makeTelemetry(enabled: true)
        let searchURL = URL.makeSearchURL(query: "test query", forceSearchQuery: true)
        telemetry.navigationCompleted(url: searchURL)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageSERP.name)
    }

    func testNavigationCompleted_WithWebsiteURL_FiresWebsitePixel() {
        let telemetry = makeTelemetry(enabled: true)
        let websiteURL = URL(string: "https://example.com/path")!
        telemetry.navigationCompleted(url: websiteURL)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageWebsite.name)
    }

    func testDuckAIUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.duckAIUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageDuckAI.name)
    }

    func testTabManagerUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.tabManagerUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageTabManager.name)
    }

    func testDataClearingUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.dataClearingUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageDataClearing.name)
    }

    func testNewTabPageUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.newTabPageUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageNewTabPage.name)
    }

    func testSettingsUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.settingsUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageSettings.name)
    }

    func testBookmarksPageUsed_FireExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.bookmarksPageUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsageBookmarksPage.name)
    }

    func testPasswordsPageUsed_FiresExpectedPixel() {
        let telemetry = makeTelemetry(enabled: true)
        telemetry.passwordsPageUsed()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.productTelemeterySurfaceUsagePasswordsPage.name)
    }

}
