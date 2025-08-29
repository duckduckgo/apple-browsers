//
//  DuckPlayerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

class DuckPlayerTests: UITestCase {
    private var addressBarTextField: XCUIElement!

    private static let searchURL = "https://duckduckgo.com/?q=%22DuckDuckGo+vs+Google%3A+5+Reasons+You+Should+Switch%E2%80%9D+site%3Ayoutube.com&atb=v469-1-wb&ia=web"
    private static let youtubeVideoTitle = "DuckDuckGo vs Google: 5 Reasons You Should Switch"
    private static let organicVideoTitle = "DuckDuckGo vs Google: 5 Reasons You Should Switch - YouTube"
    private static let duckPlayerTabPreffix = "Duck Player - "
    private static let videoTitle = "Videos"
    private static let duckURLForVideo = "duck://player/3ml7yeKBUhc"
    private static let youtubeURLForVideo = "https://www.youtube.com/watch?v=3ml7yeKBUhc"
    private static let youtubeVideoSearchURL = "https://www.youtube.com/results?search_query=%22DuckDuckGo+vs+Google%3A+5+Reasons+You+Should+Switch%22&sp=EgIQAQ%253D%253D"
    private static let watchOnDuckPlayerLink = "Watch in Duck Player"
    private static let watchOnYouTubeLink = "Watch on YouTube"
    private static let turnOnDuckPlayer = "Turn On Duck Player"
    private static let duckPlayerLoadDelay = 5.0

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        addressBarTextField = app.addressBar
        app.enforceSingleWindow()
    }

    private func openURL(url: String) {
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        addressBarTextField.pasteURL(URL(string: url)!)
    }

    private func openDuckPlayerSettings() {
        app.openPreferencesWindow()

        let scrollView = app.scrollViews.element(boundBy: 0)
        scrollView.swipeUp()

        let duckPlayerButton = app.buttons["PreferencesSidebar.duckplayerButton"]
        duckPlayerButton.click()
    }

    private func selectAlwaysOpenInDuckPlayer() {
        let alwaysOpenRadioButton = app.radioButtons["DuckPlayerMode.enabled"]
        alwaysOpenRadioButton.click()
    }

    private func selectNeverOpenInDuckPlayer() {
        let alwaysOpenRadioButton = app.radioButtons["DuckPlayerMode.disabled"]
        alwaysOpenRadioButton.click()
    }

    private func selectAskOpenInDuckPlayer() {
        let alwaysOpenRadioButton = app.radioButtons["DuckPlayerMode.alwaysAsk"]
        alwaysOpenRadioButton.click()
    }

    private func verifyDuckPlayerLoads() {
        // Give the page time to load
        sleep(2)

        // Get the DuckPlayer webview
        let duckPlayerWebView = app.windows.firstMatch.webViews["\(Self.duckPlayerTabPreffix)\(Self.youtubeVideoTitle)"]

        // Validate DuckPlayer View Exists
        XCTAssertTrue(
            duckPlayerWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Duck Player did not load with the expected title in a reasonable timeframe."
        )

        // Focus the address bar first, then get its value
        let urlValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(
            urlValue.contains(Self.duckURLForVideo),
            "URL should be DuckPlayer, but was: \(urlValue)"
        )

    }

    private func verifyYoutubeLoads() {
        // Give the page time to load
        sleep(5)

        // Get the YouTube view
        let youtubeWebView = app.windows.firstMatch.webViews["\(Self.organicVideoTitle)"]

        // Validate YouTube page loaded
        XCTAssertTrue(
            youtubeWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence + Self.duckPlayerLoadDelay),
            "YouTube webview did not load in a reasonable timeframe."
        )

        // Focus the address bar first, then get its value
        let urlValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(
            urlValue.contains("youtube.com"),
            "URL should contain youtube.com, but was: \(urlValue)"
        )
    }

    private func closeNonDuckPlayerTabs() throws {
        // Close Opener tab
        let nonDuckPlayerTabs = app.radioButtons.matching(identifier: "TabBarViewItem")
            .matching(.not(.keyPath(\.title, beginsWith: "Duck Player")))
        var count = nonDuckPlayerTabs.count
        while count > 0 {
            let tab = nonDuckPlayerTabs.firstMatch
            try tab.closeTab()
            let newCount = nonDuckPlayerTabs.count
            XCTAssertNotEqual(count, newCount)
            count = newCount
        }

    }

    // MARK: - Tests

    func test_DuckPlayer_AlwaysEnabled_Opens_FromSERPOrganic() throws {
        // Skip this test on macOS 13
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion == 13 {
            throw XCTSkip("Test disabled on macOS 13")
        }

        // Settings
        openDuckPlayerSettings()
        selectAlwaysOpenInDuckPlayer()
        app.closeCurrentTab()

        // Search
        openURL(url: Self.searchURL)

        // Click Link
        let organicVideo = app.links.containing(.staticText, identifier: Self.organicVideoTitle).firstMatch
        XCTAssertTrue(organicVideo.waitForExistence(timeout: UITests.Timeouts.navigation))
        organicVideo.click()
        sleep(2)

        try closeNonDuckPlayerTabs()
        verifyDuckPlayerLoads()
    }

    func test_DuckPlayer_AlwaysEnabled_Opens_FromSERPVideos() throws {
        // Skip this test on macOS 13
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion == 13 {
            throw XCTSkip("Test disabled on macOS 13")
        }

        // Settings
        openDuckPlayerSettings()
        selectAlwaysOpenInDuckPlayer()
        app.closeCurrentTab()

        // Search
        openURL(url: Self.searchURL)

        // Click links
        let videoLink = app.links.containing(.staticText, identifier: Self.videoTitle).firstMatch
        XCTAssertTrue(videoLink.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        videoLink.click()
        sleep(2)

        let carouselVideo = app.links.containing(.staticText, identifier: Self.youtubeVideoTitle).firstMatch
        XCTAssertTrue(carouselVideo.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        carouselVideo.click()
        sleep(2)

        try closeNonDuckPlayerTabs()

        verifyDuckPlayerLoads()
    }

    func test_DuckPlayer_Disabled_DoesNotOpen_FromSERPOrganic() throws {
        // Settings
        openDuckPlayerSettings()
        selectNeverOpenInDuckPlayer()
        app.closeCurrentTab()

        // Search
        openURL(url: Self.searchURL)

        let organicVideo = app.links.containing(.staticText, identifier: Self.organicVideoTitle).firstMatch
        XCTAssertTrue(organicVideo.waitForExistence(timeout: UITests.Timeouts.navigation))
        organicVideo.click()
        sleep(2)

        verifyYoutubeLoads()

        // Turn On YouTube Button not be present
        let watchLink = app.links.containing(.staticText, identifier: Self.turnOnDuckPlayer).firstMatch
        XCTAssertFalse(watchLink.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    func test_DuckPlayer_Disabled_DoesNotOpen_FromSERPVideo() throws {
        // Settings
        openDuckPlayerSettings()
        selectNeverOpenInDuckPlayer()
        app.closeCurrentTab()

        // Search
        openURL(url: Self.searchURL)

        let videoLink = app.links.containing(.staticText, identifier: Self.videoTitle).firstMatch
        XCTAssertTrue(videoLink.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        videoLink.click()
        sleep(2)

        let carouselVideo = app.links.containing(.staticText, identifier: Self.youtubeVideoTitle).firstMatch
        XCTAssertTrue(carouselVideo.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        carouselVideo.click()
        sleep(2)

        verifyYoutubeLoads()

        // Turn On YouTube Button not be present
        let watchLink = app.links.containing(.staticText, identifier: Self.turnOnDuckPlayer).firstMatch
        XCTAssertFalse(watchLink.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    // MARK:  Ask Mode - Serp
    func test_DuckPlayer_AskMode_ShowsOverlay_FromSERPAndOpensInDuckPlayer() throws {

        // Settings
        openDuckPlayerSettings()
        selectAskOpenInDuckPlayer()
        app.closeCurrentTab()

        // Search
        openURL(url: Self.searchURL)

        let organicVideo = app.links.containing(.staticText, identifier: Self.organicVideoTitle).firstMatch
        XCTAssertTrue(organicVideo.waitForExistence(timeout: UITests.Timeouts.navigation))
        organicVideo.click()

        sleep(2)

        verifyYoutubeLoads()

    }

    func test_DuckPlayer_AskMode_Opens_FromDirectNavigation() throws {
        // Settings
        openDuckPlayerSettings()
        selectAskOpenInDuckPlayer()
        app.closeCurrentTab()

        openURL(url: Self.duckURLForVideo)

        verifyDuckPlayerLoads()
    }

    func test_DuckPlayer_AlwaysEnabled_Opens_FromDirectYouTubeNavigation() throws {
        // Settings
        openDuckPlayerSettings()
        selectAlwaysOpenInDuckPlayer()
        app.closeCurrentTab()

        // Search
        openURL(url: Self.youtubeURLForVideo)

        verifyDuckPlayerLoads()
    }

}
