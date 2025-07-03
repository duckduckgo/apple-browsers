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
      mockSettings = MockDuckPlayerSettings(appSettings: AppSettingsMock(),
                                            privacyConfigManager: MockPrivacyConfigurationManager(),
                                            featureFlagger: MockDuckPlayerFeatureFlagger(),
                                            internalUserDecider: MockInternalUserDecider())
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
        viewModel.source = .serp

        // Then
        XCTAssertTrue(viewModel.shouldShowYouTubeButton, "YouTube button should be shown in portrait mode from SERP")
    }

    @MainActor
    func testNoUIIsShown_WhenLandscape() {
        // Given
        viewModel.isLandscape = true

        // Then
        XCTAssertFalse(viewModel.shouldShowYouTubeButton, "YouTube button should not be shown in landscape mode")
        XCTAssertFalse(viewModel.shouldShowAutoOpenToggle, "Auto-open toggle should not be shown in landscape mode")
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should not be shown in landscape mode")
    }

    @MainActor
    func testShouldShowYouTubeButton_WhenNotSerp_ShouldBeFalse() {
        // Given
        viewModel = DuckPlayerViewModel(videoID: "testVideoID", duckPlayerSettings: mockSettings, source: .other)

        // Then
        XCTAssertFalse(viewModel.shouldShowYouTubeButton, "YouTube button should not be shown when source is not SERP")

        // Given
        viewModel = DuckPlayerViewModel(videoID: "testVideoID", duckPlayerSettings: mockSettings, source: .youtube)

        // Then
        XCTAssertFalse(viewModel.shouldShowYouTubeButton, "YouTube button should not be shown when source is not SERP")
    }

    @MainActor
    func testShouldShowWelcomeMessage_WhenConditionsMet_ShouldBeTrue() {
        // Given
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .nativeOptOut
        viewModel.source = .youtube

        // Then
        XCTAssertTrue(viewModel.shouldShowWelcomeMessage, "Welcome message should be shown under specific conditions")
    }
   
    @MainActor
    func testShouldShowWelcomeMessage_WhenAlreadyShown_ShouldBeFalse() {
        // Given   
        mockSettings.welcomeMessageShown = true
        mockSettings.variant = .nativeOptOut
        viewModel.source = .youtube

        // Then
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should not be shown if already shown")
    }

    @MainActor
    func testShouldShowWelcomeMessage_WhenNotNativeOptOutVariant_ShouldBeFalse() {
        // Given
        mockSettings.welcomeMessageShown = false
        mockSettings.variant = .nativeOptIn
        viewModel.source = .youtube

        // Then
        XCTAssertFalse(viewModel.shouldShowWelcomeMessage, "Welcome message should not be shown for non-native-opt-out variants")
    }

    @MainActor
    func testGetVideoURL_IncludesCorrectParametersAndTimestamp_WhenTimestampIsAboveThreshold() {
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
    func testGetVideoURL_ExcludesStartParameter_WhenTimestampIsBelowThreshold() {
        // Given
        let expectedVideoID = "testVideoID"
        let expectedTimestamp: TimeInterval = 4.9
        viewModel.timestamp = expectedTimestamp
        mockSettings.autoplay = false

        // When
        let url = viewModel.getVideoURL()

        // Then
        XCTAssertNotNil(url, "Generated URL should not be nil")
        
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        XCTAssertNil(queryItems[DuckPlayerViewModel.Constants.startParameter], "start parameter should not be included for timestamps below 5 seconds")
        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.relParameter], DuckPlayerViewModel.Constants.disabled, "rel parameter should be disabled")
        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.playsInlineParameter], DuckPlayerViewModel.Constants.enabled, "playsinline parameter should be enabled")
    }

    @MainActor
    func testGetVideoURL_IncludesStartParameter_WhenTimestampIsExactlyFive() {
        // Given
        let expectedVideoID = "testVideoID"
        let expectedTimestamp: TimeInterval = 5.0
        viewModel.timestamp = expectedTimestamp

        // When
        let url = viewModel.getVideoURL()

        // Then
        XCTAssertNotNil(url, "Generated URL should not be nil")
        
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        XCTAssertEqual(queryItems[DuckPlayerViewModel.Constants.startParameter], "5", "start parameter should be included for timestamp exactly at 5 seconds")
    }

    @MainActor
    func testGetVideoURL_ExcludesStartParameter_WhenTimestampIsZero() {
        // Given
        let expectedVideoID = "testVideoID"
        viewModel.timestamp = 0

        // When
        let url = viewModel.getVideoURL()

        // Then
        XCTAssertNotNil(url, "Generated URL should not be nil")
        
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        XCTAssertNil(queryItems[DuckPlayerViewModel.Constants.startParameter], "start parameter should not be included for timestamp of 0")
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
        let expectedCurrentTimestamp: TimeInterval = 42.0
        viewModel.currentTimeStamp = expectedCurrentTimestamp // Use currentTimeStamp instead of timestamp
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
        XCTAssertEqual(receivedTimestamp, expectedCurrentTimestamp, "Dismiss publisher should emit the current video playback timestamp")
    }

    @MainActor
    func testUpdateTimeStamp_UpdatesCurrentTimeStamp() {
        // Given
        let newTimestamp: TimeInterval = 123.45
        XCTAssertEqual(viewModel.currentTimeStamp, 0, "Initial timestamp should be 0")
        
        // When
        viewModel.updateTimeStamp(timeStamp: newTimestamp)
        
        // Then
        XCTAssertEqual(viewModel.currentTimeStamp, newTimestamp, "Current timestamp should be updated")
    }

    @MainActor
    func testDismissPublisher_WithUpdatedTimestamp() {
        // Given
        let initialTimestamp: TimeInterval = 30.0
        let updatedTimestamp: TimeInterval = 75.5
        viewModel.timestamp = initialTimestamp // Initial video position
        viewModel.updateTimeStamp(timeStamp: updatedTimestamp) // Simulate video playback progress
        
        let expectation = XCTestExpectation(description: "Dismiss publisher emitted with updated timestamp")
        var receivedTimestamp: TimeInterval?

        viewModel.dismissPublisher
            .sink { timestamp in
                receivedTimestamp = timestamp
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        viewModel.onDisappear()

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedTimestamp, updatedTimestamp, "Should emit the updated current timestamp, not the initial timestamp")
        XCTAssertNotEqual(receivedTimestamp, initialTimestamp, "Should not emit the initial timestamp")
    }


}
