//
//  DuckPlayerViewModelTests.swift
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
import Combine
@testable import DuckDuckGo
@testable import BrowserServicesKit
@testable import Core

final class DuckPlayerViewModelTests: XCTestCase {

    var viewModel: DuckPlayerViewModel!
    var mockSettings: MockDuckPlayerSettings!
    var cancellables: Set<AnyCancellable>!

    @MainActor
    override func setUp() {
        super.setUp()
        mockSettings = MockDuckPlayerSettings(appSettings: AppSettingsMock(), privacyConfigManager: MockPrivacyConfigurationManager(), internalUserDecider: MockDuckPlayerInternalUserDecider())
        viewModel = DuckPlayerViewModel(videoID: "testVideoID", duckPlayerSettings: mockSettings, source: .serp)
        cancellables = []
    }

    override func tearDown() {
        viewModel = nil
        mockSettings = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Test Cases

    @MainActor
    func testShouldShowYouTubeButton_WhenPortraitAndSerp_ShouldBeTrue() {
        // Given
        viewModel.isLandscape = false
        // Source is already .serp from setup

        // Then
        XCTAssertTrue(viewModel.shouldShowYouTubeButton, "YouTube button should be shown in portrait mode from SERP")
    }

    @MainActor
    func testShouldShowYouTubeButton_WhenLandscape_ShouldBeFalse() {
        // Given
        viewModel.isLandscape = true

        // Then
        XCTAssertFalse(viewModel.shouldShowYouTubeButton, "YouTube button should not be shown in landscape mode")
    }

    @MainActor
    func testShouldShowYouTubeButton_WhenNotSerp_ShouldBeFalse() {
        // Given
        viewModel = DuckPlayerViewModel(videoID: "testVideoID", duckPlayerSettings: mockSettings, source: .other) // Non-SERP source
        viewModel.isLandscape = false

        // Then
        XCTAssertFalse(viewModel.shouldShowYouTubeButton, "YouTube button should not be shown when source is not SERP")
    }

    @MainActor
    func testShouldShowAutoOpenToggle_WhenPortraitAndVisible_ShouldBeTrue() {
        // Given
        viewModel.isLandscape = false
        viewModel.showAutoOpenOnYoutubeToggle = true // Explicitly set, though default is true

        // Then
        XCTAssertTrue(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should be shown in portrait when not hidden")
    }

    @MainActor
    func testShouldShowAutoOpenToggle_WhenLandscape_ShouldBeFalse() {
        // Given
        viewModel.isLandscape = true

        // Then
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should not be shown in landscape mode")
    }

    @MainActor
    func testShouldShowAutoOpenToggle_WhenExplicitlyHidden_ShouldBeFalse() {
        // Given
        viewModel.isLandscape = false
        viewModel.hideAutoOpenToggle() // Hide the toggle

        // Then
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should not be shown when explicitly hidden")
    }

    @MainActor
    func testShouldShowWelcomeMessage_WhenConditionsMet_ShouldBeTrue() {
        // Given
        viewModel.isLandscape = false
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .nativeOptOut
        viewModel.hideAutoOpenToggle() // Welcome message requires toggle to be hidden

        // Then
        XCTAssertTrue(viewModel.shouldShowWelcomeMessage, "Welcome message should be shown under specific conditions")
    }

    @MainActor
    func testShouldShowWelcomeMessage_WhenLandscape_ShouldBeFalse() {
        // Given
        viewModel.isLandscape = true
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .nativeOptOut
        viewModel.hideAutoOpenToggle()

        // Then
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should not be shown in landscape")
    }

    @MainActor
    func testShouldShowWelcomeMessage_WhenAlreadyShown_ShouldBeFalse() {
        // Given
        viewModel.isLandscape = false
        mockSettings.welcomeMessageShown = true // Message already shown
        mockSettings.variant = .nativeOptOut
        viewModel.hideAutoOpenToggle()

        // Then
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should not be shown if already shown")
    }

    @MainActor
    func testShouldShowWelcomeMessage_WhenNotNativeOptOutVariant_ShouldBeFalse() {
        // Given
        viewModel.isLandscape = false
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .classicWeb // Not the required variant
        viewModel.hideAutoOpenToggle()

        // Then
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should not be shown for non-native-opt-out variants")
    }

    @MainActor
    func testShouldShowWelcomeMessage_WhenAutoOpenToggleVisible_ShouldBeFalse() {
        // Given
        viewModel.isLandscape = false
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .nativeOptOut
        viewModel.showAutoOpenOnYoutubeToggle = true // Toggle is visible

        // Then
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should not be shown when auto-open toggle is visible")
    }

    @MainActor
    func testGetVideoURL_IncludesCorrectParametersAndTimestamp() {
        // Given
        let expectedBaseURL = DuckPlayerViewModel.Constants.baseURL
        let expectedVideoID = "testVideoID"
        let expectedTimestamp: TimeInterval = 30.5
        viewModel.timestamp = expectedTimestamp
        mockSettings.autoplay = true // Example setting change

        // When
        let url = viewModel.getVideoURL()

        // Then
        XCTAssertNotNil(url, "Generated URL should not be nil")
        XCTAssertEqual(url?.scheme, "https", "URL scheme should be https")
        XCTAssertEqual(url?.host, "www.youtube-nocookie.com", "URL host should be youtube-nocookie.com")
        XCTAssertEqual(url?.path, "/embed/\(expectedVideoID)", "URL path should contain the video ID")

        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.relParameter], DuckPlayerViewModel.Constants.disabled, "rel parameter should be disabled")
        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.playsInlineParameter], DuckPlayerViewModel.Constants.enabled, "playsinline parameter should be enabled")
        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.colorSchemeParameter], DuckPlayerViewModel.Constants.colorSchemeValue, "color parameter should be white")
        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.autoplayParameter], DuckPlayerViewModel.Constants.enabled, "autoplay parameter should be enabled based on settings")
        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.startParameter], String(Int(expectedTimestamp)), "start parameter should match the timestamp")
    }

    @MainActor
    func testOrientationChange_UpdatesStateCorrectly() {
        // Given: Initial state is portrait (default or set)
        viewModel.isLandscape = false
        viewModel.showAutoOpenOnYoutubeToggle = true
        mockSettings.nativeUIYoutubeMode = .ask // Ensure autoOpenOnYoutube is false
        viewModel.autoOpenOnYoutube = false

        // Simulate NotificationCenter posting landscape orientation
        // We can't directly simulate the NotificationCenter, so we call updateOrientation directly
        // and manually set the window scene orientation (which updateOrientation would read)
        // This requires a bit more setup or a mock UIWindowScene, so we'll just test the logic flow triggered by orientation change.
        // We'll simulate landscape by setting isLandscape directly and verifying dependent properties.

        // When: Simulate landscape orientation update
        viewModel.isLandscape = true
        // Manually call update to reflect potential side effects (like hiding toggle)
        viewModel.updateOrientation() // In a real test env, this might be triggered by notification

        // Then: Verify state in landscape
        XCTAssertTrue(viewModel.isLandscape, "isLandscape should be true after orientation change")
        XCTAssertFalse(viewModel.shouldShowYouTubeButton, "YouTube button should be hidden in landscape")
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should be hidden in landscape")

        // When: Simulate portrait orientation update
        viewModel.isLandscape = false
        // Manually call update
        viewModel.updateOrientation() // In a real test env, this might be triggered by notification

        // Then: Verify state restored in portrait
        XCTAssertFalse(viewModel.isLandscape, "isLandscape should be false after orientation change back to portrait")
        XCTAssertTrue(viewModel.shouldShowYouTubeButton, "YouTube button should be shown again in portrait (assuming SERP source)")
        XCTAssertTrue(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should be shown again in portrait (assuming not explicitly hidden and autoOpen=false)")

        // Test case where toggle remains hidden if auto-open is true
        mockSettings.nativeUIYoutubeMode = .auto
        viewModel.autoOpenOnYoutube = true
        viewModel.isLandscape = true // Go to landscape
        viewModel.updateOrientation()
        viewModel.isLandscape = false // Back to portrait
        viewModel.updateOrientation()
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should remain hidden in portrait if autoOpen is true")
    }
}

