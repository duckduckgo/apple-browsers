//
//  DuckPlayerNativeUIPresenterTests.swift
//  DuckDuckGo
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
import Combine
import SwiftUI
import UIKit

@testable import DuckDuckGo

final class DuckPlayerNativeUIPresenterTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: DuckPlayerNativeUIPresenter!
    private var mockHostViewController: MockDuckPlayerHostingViewControlling!
    private var mockAppSettings: AppSettingsMock!
    private var mockChromeDelegate: MockDuckPlayerChromeDelegate!
    private var mockPrivacyConfig: PrivacyConfigurationManagerMock!
    private var mockInternalUserDecider: MockDuckPlayerInternalUserDecider!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        mockHostViewController = MockDuckPlayerHostingViewControlling()
        mockChromeDelegate = MockDuckPlayerChromeDelegate()
        mockHostViewController.duckPlayerChromeDelegate = mockChromeDelegate
        mockHostViewController.webViewBottomAnchorConstraint = NSLayoutConstraint()
        
        mockAppSettings = AppSettingsMock()
        mockPrivacyConfig = PrivacyConfigurationManagerMock()
        mockInternalUserDecider = MockDuckPlayerInternalUserDecider()
        
        sut = DuckPlayerNativeUIPresenter(appSettings: mockAppSettings)
        cancellables = []
        
        // Reset static mock state
        //MockDuckPlayerToastView.reset()
    }
    
    override func tearDown() {
        sut = nil
        mockHostViewController = nil
        mockAppSettings = nil
        mockChromeDelegate = nil
        mockPrivacyConfig = nil
        mockInternalUserDecider = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - presentPill Tests
    
    @MainActor
    func testPresentPill_WhenFirstTimeInVideo_ShowsEntryPill() {
        // Given
        let videoID = "kaajas891"
        let timestamp: TimeInterval? = 100
        
        // When
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)

        // Then
        guard let pill = sut.hostView?.view else {
            XCTFail("Pill view not found")
            return
        }
        
        // We should only have one subview
        XCTAssertEqual(pill.subviews.count, 1)
        XCTAssertEqual(sut.state.hasBeenShown, true)
        XCTAssertEqual(sut.state.videoID, "kaajas891")
        XCTAssertEqual(sut.state.timestamp, 100)
        
    }
    
    @MainActor
    func testPresentPill_WhenSecondTime_ShowsReEntryPill() {
        // Given
        let videoID = "kaajas891"
        let timestamp: TimeInterval? = 100
        
        // When
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)

        // Then
        guard let pill = sut.hostView?.view else {
            XCTFail("Pill view not found")
            return
        }
        
        // We should only have one subview
        XCTAssertEqual(pill.subviews.count, 1)
        XCTAssertEqual(sut.pillType, .reEntry)
    }
    
    @MainActor
    func testPresentPill_WhenPrimingModalShouldShow_ShowsPrimingModal() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = nil
        mockAppSettings.duckPlayerNativeUIPrimingModalPresentationEventCount = 0
        mockAppSettings.duckPlayerNativeUIPrimingModalTimeSinceLastPresented = 0
        mockAppSettings.duckPlayerNativeYoutubeMode = .ask
        
        // When
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        
        // Then
        XCTAssertTrue(mockHostViewController.presentCalled)
        XCTAssertEqual(mockAppSettings.duckPlayerNativeUIPrimingModalPresentationEventCount, 1)
    }
    
    // MARK: - dismissPill Tests
    
    @MainActor
    func testDismissPill_WhenProgramatic_DoesNotIncrementDismissCount() {
        // Given
        let initialCount = mockAppSettings.duckPlayerPillDismissCount
        
        // When
        sut.dismissPill(reset: false, animated: true, programatic: true)
        
        // Then
        XCTAssertEqual(mockAppSettings.duckPlayerPillDismissCount, initialCount)
    }
    
    @MainActor
    func testDismissPill_WhenUserDismissed_IncrementsDismissCount() {
        // Given
        let initialCount = mockAppSettings.duckPlayerPillDismissCount
        
        // When
        sut.dismissPill(reset: false, animated: true, programatic: false)
        
        // Then
        XCTAssertEqual(mockAppSettings.duckPlayerPillDismissCount, initialCount + 1)
    }
    
    /*
    @MainActor
    func testDismissPill_WhenDismissCountReachesThreshold_ShowsToast() {
        // Given
        mockAppSettings.duckPlayerPillDismissCount = 2
        
        // When
        sut.dismissPill(reset: false, animated: true, programatic: false)
        
        // Then
        XCTAssertTrue(MockDuckPlayerToastView.presentCalled)
        XCTAssertEqual(mockAppSettings.duckPlayerPillDismissCount, 3)
    }
     */
    
    @MainActor
    func testDismissPill_WhenReset_ResetsState() {
        // Given
        let videoID = "test123"
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: nil)
        
        // When
        sut.dismissPill(reset: true, animated: true, programatic: true)
        
        // Then
        // Note: We can't directly test the private state, but we can verify the behavior
        // by presenting again and checking it shows as a first-time presentation
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: nil)
        XCTAssertTrue(mockHostViewController.presentCalled)
    }
    
    // MARK: - presentDuckPlayer Tests
    
    @MainActor
    func testPresentDuckPlayer_ResetsDismissCountIfBelowThreshold() {
        // Given
        mockAppSettings.duckPlayerPillDismissCount = 2
        
        // When
        _ = sut.presentDuckPlayer(
            videoID: "test123",
            source: .youtube,
            in: mockHostViewController,
            title: nil,
            timestamp: nil
        )
        
        // Then
        XCTAssertEqual(mockAppSettings.duckPlayerPillDismissCount, 0)
    }
    
    @MainActor
    func testPresentDuckPlayer_DoesNotResetDismissCountIfAboveThreshold() {
        // Given
        mockAppSettings.duckPlayerPillDismissCount = 3
        
        // When
        _ = sut.presentDuckPlayer(
            videoID: "test123",
            source: .youtube,
            in: mockHostViewController,
            title: nil,
            timestamp: nil
        )
        
        // Then
        XCTAssertEqual(mockAppSettings.duckPlayerPillDismissCount, 3)
    }
    
    /*
    @MainActor
    func testPresentDuckPlayer_WhenNonYoutubeSource_SendsNavigationRequest() {
        // Given
        let videoID = "test123"
        var receivedURL: URL?
        
        // When
        let (navigation, _) = sut.presentDuckPlayer(
            videoID: videoID,
            source: .vimeo,
            in: mockHostViewController,
            title: nil,
            timestamp: nil
        )
        
        navigation.sink { url in
            receivedURL = url
        }.store(in: &cancellables)
        
        // Then
        XCTAssertTrue(mockHostViewController.presentCalled)
        XCTAssertNotNil(receivedURL)
    }
     */
    
    // MARK: - Chrome Visibility Tests
    
    @MainActor
    func testHideBottomSheetForHiddenChrome_DisablesUserInteraction() {
        // Given
        sut.presentPill(for: "test123", in: mockHostViewController, timestamp: nil)
        
        // When
        sut.hideBottomSheetForHiddenChrome()
        
        // Then
        XCTAssertFalse(mockHostViewController.view.isUserInteractionEnabled)
    }
    
    @MainActor
    func testShowBottomSheetForVisibleChrome_EnablesUserInteraction() {
        // Given
        sut.presentPill(for: "test123", in: mockHostViewController, timestamp: nil)
        sut.hideBottomSheetForHiddenChrome()
        
        // When
        sut.showBottomSheetForVisibleChrome()
        
        // Then
        XCTAssertTrue(mockHostViewController.view.isUserInteractionEnabled)
    }
    
    
    
    // MARK: - Video Playback Request Tests
    
    @MainActor
    func testVideoPlaybackRequest_WhenPillOpened_SendsRequest() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = 30
        var receivedRequest: (videoID: String, timestamp: TimeInterval?)?
        
        sut.videoPlaybackRequest.sink { request in
            receivedRequest = request
        }.store(in: &cancellables)
        
        // When
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        
        // Then
        XCTAssertNotNil(receivedRequest)
        XCTAssertEqual(receivedRequest?.videoID, videoID)
        XCTAssertEqual(receivedRequest?.timestamp, timestamp)
    }
}

