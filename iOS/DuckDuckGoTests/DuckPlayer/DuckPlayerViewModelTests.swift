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

    // MARK: - Orientation Dependent Tests

    @MainActor
    func testComputedProperties_WhenLandscape() {
        // Given: ViewModel is configured for SERP source initially
        viewModel.showAutoOpenOnYoutubeToggle = true // Start with toggle visible
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .nativeOptOut

        // When: Set orientation to landscape
        viewModel.isLandscape = true

        // Then: Verify computed properties dependent on landscape state
        XCTAssertTrue(viewModel.isLandscape, "isLandscape should be true")
        XCTAssertFalse(viewModel.shouldShowYouTubeButton, "YouTube button should be hidden in landscape")
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should be hidden in landscape")
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should be hidden in landscape")
    }

    @MainActor
    func testComputedProperties_WhenPortrait() {
        // Given: ViewModel is configured for SERP source initially
        mockSettings.nativeUIYoutubeMode = .ask // Ensure autoOpenOnYoutube is initially false
        viewModel.autoOpenOnYoutube = false
        viewModel.showAutoOpenOnYoutubeToggle = true // Assume toggle is visible initially
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .nativeOptOut

        // When: Set orientation to portrait
        viewModel.isLandscape = false

        // Then: Verify computed properties dependent on portrait state
        XCTAssertFalse(viewModel.isLandscape, "isLandscape should be false")
        XCTAssertTrue(viewModel.shouldShowYouTubeButton, "YouTube button should be shown in portrait for SERP source")
        XCTAssertTrue(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should be shown in portrait when visible flag is true")

        // Verify welcome message depends on toggle state (it should be hidden if toggle is visible)
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should be hidden when auto-open toggle is visible")

        // Test case: Welcome message shown when toggle is hidden
        viewModel.hideAutoOpenToggle() // Explicitly hide toggle
        XCTAssertTrue(viewModel.shouldShowWelcomeMessage, "Welcome message should be shown when toggle is hidden and other conditions met")

        // Test case: Auto-open toggle remains hidden if explicitly hidden
        viewModel.hideAutoOpenToggle()
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should remain hidden if explicitly hidden")
    }

    @MainActor
    func testAutoOpenToggleVisibility_WhenPortraitAndAutoOpenIsTrue() {
        // Given
        mockSettings.nativeUIYoutubeMode = .auto
        viewModel.autoOpenOnYoutube = true
        viewModel.isLandscape = false // Ensure portrait
        viewModel.showAutoOpenOnYoutubeToggle = true // Start with toggle notionally visible

        // Then
        XCTAssertTrue(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle visibility should be true when showAutoOpenOnYoutubeToggle is true, even if autoOpenOnYoutube is true")

        // When: Explicitly hide the toggle
        viewModel.hideAutoOpenToggle()

        // Then
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should be hidden after calling hideAutoOpenToggle()")
    }

    // MARK: - State Mutation Tests

    @MainActor
    func testHideWelcomeMessage_SetsFlagInSettings() {
        // Given
        mockSettings.welcomeMessageShown = false // Ensure initial state

        // When
        viewModel.hideWelcomeMessage()

        // Then
        XCTAssertTrue(mockSettings.welcomeMessageShown, "welcomeMessageShown flag should be true after hiding the message")
    }

    // MARK: - Publisher Tests

    @MainActor
    func testYoutubeNavigationRequestPublisher_OnHandleYouTubeNavigation() {
        // Given
        let expectedVideoID = "navigatedVideoID"
        let testURL = URL(string: "https://www.youtube.com/watch?v=\(expectedVideoID)")!
        let expectation = XCTestExpectation(description: "YouTube navigation request publisher emitted")
        var receivedVideoID: String?

        viewModel.youtubeNavigationRequestPublisher
            .sink { videoID in
                receivedVideoID = videoID
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.handleYouTubeNavigation(testURL)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedVideoID, expectedVideoID, "Publisher should emit the correct video ID from the URL")
    }

    @MainActor
    func testYoutubeNavigationRequestPublisher_OnOpenInYouTube() {
        // Given
        let expectation = XCTestExpectation(description: "YouTube navigation request publisher emitted")
        var receivedVideoID: String?

        viewModel.youtubeNavigationRequestPublisher
            .sink { videoID in
                receivedVideoID = videoID
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.openInYouTube()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedVideoID, viewModel.videoID, "Publisher should emit the viewModel's video ID")
    }

    @MainActor
    func testSettingsRequestPublisher_OnOpenSettings() {
        // Given
        let expectation = XCTestExpectation(description: "Settings request publisher emitted")

        viewModel.settingsRequestPublisher
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.openSettings()

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testDismissPublisher_OnDisappear() {
        // Given
        let expectedTimestamp: TimeInterval = 42.0
        viewModel.timestamp = expectedTimestamp
        let expectation = XCTestExpectation(description: "Dismiss publisher emitted")
        var receivedTimestamp: TimeInterval?

        viewModel.dismissPublisher
            .sink { timestamp in
                receivedTimestamp = timestamp
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.onDisappear() // This triggers the publisher

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedTimestamp, expectedTimestamp, "Dismiss publisher should emit the current timestamp")
    }

    // MARK: - Timestamp Observation Tests
    // Note: Testing the timer scheduling directly is tricky. We test the effect.
    @MainActor
    func testTimestampObservation_UpdatesTimestampPeriodically() async {
        // Given
        let mockWebView = MockWebView()
        // We need a viewModel instance to initialize the Coordinator subclass
        let tempViewModel = DuckPlayerViewModel(videoID: "coordInit")
        let mockCoordinator = TestableDuckPlayerWebViewCoordinator(viewModel: tempViewModel)
        let initialTimestamp: TimeInterval = 0
        let updatedTimestamp: TimeInterval = 5.0

        viewModel.timestamp = initialTimestamp
        mockCoordinator.mockTimestamp = updatedTimestamp

        // When: Start observing
        viewModel.startObservingTimestamp(webView: mockWebView, coordinator: mockCoordinator)

        // Then: Verify timestamp is updated after a short delay (simulating timer firing)
        // We need to wait slightly longer than the timer interval (0.3s)
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds

        // Perform the check
        await MainActor.run {
            XCTAssertEqual(viewModel.timestamp, updatedTimestamp, "Timestamp should be updated by the observer")
            XCTAssertGreaterThan(mockCoordinator.getCurrentTimestampCallCount, 0, "getCurrentTimestamp should have been called")
        }

        // When: Stop observing
        let callCountBeforeStop = mockCoordinator.getCurrentTimestampCallCount
        viewModel.stopObservingTimestamp()

        // Wait again to ensure no more updates happen
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds

        await MainActor.run {
             XCTAssertEqual(mockCoordinator.getCurrentTimestampCallCount, callCountBeforeStop, "getCurrentTimestamp should not be called after stopping observation")
        }
        
        // Ensure timestamp didn't change further
        XCTAssertEqual(viewModel.timestamp, updatedTimestamp, "Timestamp should remain unchanged after stopping observation")
    }

}

