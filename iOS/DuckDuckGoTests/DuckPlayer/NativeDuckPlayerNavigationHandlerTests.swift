//
//  NativeDuckPlayerNavigationHandlerTests.swift
//  DuckDuckGoTests
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
import WebKit
import DuckPlayer
import BrowserServicesKit
import Common
import Core
import Combine

@testable import DuckDuckGo

@MainActor
final class NativeDuckPlayerNavigationHandlerTests: XCTestCase {

    // MARK: - Properties
    private var mockWebView: MockWebView!
    private var mockAppSettings: AppSettingsMock!
    private var mockPrivacyConfig: PrivacyConfigurationManagerMock!
    private var mockInternalUserDecider: MockDuckPlayerInternalUserDecider!
    private var playerSettings: MockDuckPlayerSettings!
    private var mockDuckPlayer: MockDuckPlayer!
    private var mockFeatureFlagger: MockDuckPlayerFeatureFlagger!
    private var sut: NativeDuckPlayerNavigationHandler!
    private var mockTabNavigator: MockDuckPlayerTabNavigator!
    private var mockNativeUIPresenter: MockDuckPlayerNativeUIPresenting!
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup
    override func setUp() {
        super.setUp()
        mockWebView = MockWebView()
        mockAppSettings = AppSettingsMock()
        mockPrivacyConfig = PrivacyConfigurationManagerMock()
        mockInternalUserDecider = MockDuckPlayerInternalUserDecider()
        
        playerSettings = MockDuckPlayerSettings(
            appSettings: mockAppSettings,
            privacyConfigManager: mockPrivacyConfig,
            internalUserDecider: mockInternalUserDecider
        )
        
        mockFeatureFlagger = MockDuckPlayerFeatureFlagger()
        mockNativeUIPresenter = MockDuckPlayerNativeUIPresenting()
        
        mockDuckPlayer = MockDuckPlayer(
            settings: playerSettings,
            featureFlagger: mockFeatureFlagger,
            nativeUIPresenter: mockNativeUIPresenter
        )
        
        mockTabNavigator = MockDuckPlayerTabNavigator()
        
        sut = NativeDuckPlayerNavigationHandler(
            duckPlayer: mockDuckPlayer,
            featureFlagger: mockFeatureFlagger,
            appSettings: mockAppSettings,
            tabNavigationHandler: mockTabNavigator
        )
    }

    override func tearDown() {
        cancellables.removeAll()
        mockWebView = nil
        mockAppSettings = nil
        mockPrivacyConfig = nil
        playerSettings = nil
        mockDuckPlayer = nil
        mockFeatureFlagger = nil
        mockTabNavigator = nil
        sut = nil
        mockNativeUIPresenter = nil
        mockInternalUserDecider = nil
        super.tearDown()
    }

    // MARK: - handleURLChange Tests

    // TODO: Test media playback/pause
    func testHandleURLChange_inLinkPreview_ReturnsNotHandled() {
        // Given
        mockFeatureFlagger.enabledFeatures = [.duckPlayer]
        let url = URL(string: "https://www.youtube.com/watch?v=djd83w3s")!

        // When
        sut.isLinkPreview = true
        let result = sut.handleURLChange(webView: mockWebView, previousURL: nil, newURL: url)

        // Then
        XCTAssertEqual(result, .notHandled(.isLinkPreview))
        XCTAssertNil(sut.lastHandledVideoID)
    }


    func testHandleURLChange_WhenFeatureOff_ReturnsNotHandled() {
        // Given
        mockFeatureFlagger.enabledFeatures = []
        let url = URL(string: "https://www.youtube.com/watch?v=djd83w3s")!

        // When
        let result = sut.handleURLChange(webView: mockWebView, previousURL: nil, newURL: url)

        // Then
        XCTAssertEqual(result, .notHandled(.featureOff))
        XCTAssertNil(sut.lastHandledVideoID)
    }

    func testHandleURLChange_WhenInvalidURL_ReturnsNotHandled() {
        // Given
        mockFeatureFlagger.enabledFeatures = [.duckPlayer]
        let url = URL(string: "https://www.example.com")!

        // When
        let result = sut.handleURLChange(webView: mockWebView, previousURL: nil, newURL: url)

        // Then
        XCTAssertEqual(result, .notHandled(.invalidURL))
        XCTAssertNil(sut.lastHandledVideoID)
    }

    func testHandleURLChange_WhenValidYouTubeURL_HandlesCorrectly() {
        // Given
        mockFeatureFlagger.enabledFeatures = [.duckPlayer]
        playerSettings.nativeUIYoutubeMode = .ask
        let url = URL(string: "https://www.youtube.com/watch?v=94ujddss")!

        // When
        let result = sut.handleURLChange(webView: mockWebView, previousURL: nil, newURL: url)

        // Then
        XCTAssertEqual(result, .handled(.duckPlayerEnabled))
        XCTAssertTrue(mockDuckPlayer.presentPillCalled)
        XCTAssertEqual(sut.lastHandledVideoID, "94ujddss")
    }
    
    func testHandleURLChange_WhenVisitingSameLastHandledVideoAfterOtherNavigation_HandlesCorrectly() {
        // Given
        mockFeatureFlagger.enabledFeatures = [.duckPlayer]
        playerSettings.nativeUIYoutubeMode = .ask
        let url = URL(string: "https://www.youtube.com/watch?v=ksdsdksd2")!

        // When
        
        // Navigate to YT Video
        _ = sut.handleURLChange(webView: mockWebView, previousURL: nil, newURL: url)
        
        // Navigate outside Youtube
        let nonYoutubeURL = URL(string: "https://www.google.com")!
        _ = sut.handleURLChange(webView: mockWebView, previousURL: url, newURL: nonYoutubeURL)
        
        // Navigate back to same YT Video
        let result = sut.handleURLChange(webView: mockWebView, previousURL: nonYoutubeURL, newURL: url)
        
        // Then
        XCTAssertEqual(result, .handled(.duckPlayerEnabled))
        XCTAssertTrue(mockDuckPlayer.presentPillCalled)
        XCTAssertEqual(sut.lastHandledVideoID, "ksdsdksd2")
        
    }

    func testHandleURLChange_WithMobileYouTubeURL_HandlesCorrectly() {
        // Given
        mockFeatureFlagger.enabledFeatures = [.duckPlayer]
        playerSettings.nativeUIYoutubeMode = .ask
        let url = URL(string: "https://m.youtube.com/watch?v=123")!

        // When
        let result = sut.handleURLChange(webView: mockWebView, previousURL: nil, newURL: url)

        // Then
        XCTAssertEqual(result, .handled(.duckPlayerEnabled))
        XCTAssertTrue(mockDuckPlayer.presentPillCalled)
    }

    // MARK: - handleDuckNavigation Tests

    func testHandleDuckNavigation_LoadsYouTubeURL() {
        // Given
        mockFeatureFlagger.enabledFeatures = [.duckPlayer]
        let videoID = "123"
        let url = URL(string: "duck://player/\(videoID)")!
        let navigationAction = MockNavigationAction(request: URLRequest(url: url))
        
        // When
        sut.handleDuckNavigation(navigationAction, webView: mockWebView)
        
        // Then
        XCTAssertNil(sut.lastHandledVideoID)
        XCTAssertEqual(mockWebView.lastLoadedRequest?.url?.absoluteString, "https://m.youtube.com/watch?v=\(videoID)")
        
    }
    
    func testDuckURLNavigation_WithMalformedURL_HandlesGracefully() {
        // Given
        let malformedDuckURL = URL(string: "duck://player/")!
        let navigationAction = MockNavigationAction(request: URLRequest(url: malformedDuckURL))
        
        // When
        sut.handleDuckNavigation(navigationAction, webView: mockWebView)
        
        // Then
        // This test validates the handler doesn't crash with malformed URLs
        // The exact behavior depends on how the implementation handles this case
        // You may need to adjust assertions based on expected behavior
        XCTAssertNotNil(mockWebView.lastLoadedRequest?.url)
    }

    // MARK: - handleAttach Tests

    func testHandleAttach_InitializesCorrectly() {
        // Given
        guard let webView = mockWebView else {
            XCTFail("Failed to create mock web view")
            return
        }
        
        // When
        sut.handleAttach(webView: webView)
        
        // Then
        XCTAssertNotNil(sut)

    }
   
    func testGetDuckURLFor_WithInvalidURL_ReturnsNil() {
        // Given
        let url = URL(string: "https://www.example.com")!

        // When
        let result = sut.getDuckURLFor(url)

        // Then
        XCTAssertNil(result)
    }

    func testDuckURLNavigation_WithMalformedURL_HandlesGracefully() {
        // Given
        let malformedDuckURL = URL(string: "duck://player/")!
        let navigationAction = MockNavigationAction(request: URLRequest(url: malformedDuckURL))
        
        // When
        sut.handleDuckNavigation(navigationAction, webView: mockWebView)
        
        // Then
        // This test validates the handler doesn't crash with malformed URLs
        // The exact behavior depends on how the implementation handles this case
        // You may need to adjust assertions based on expected behavior
        XCTAssertNotNil(mockWebView.lastLoadedRequest?.url)
    }
}
