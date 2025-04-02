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

extension DuckPlayerNativeUIPresenterTests {
    struct Constants {
        static let webViewRequiredBottomConstraint: CGFloat = 90
    }
}

class TestNotificationCenter: NotificationCenter {
    var postedNotifications: [Notification] = []
    
    override func post(_ notification: Notification) {
        postedNotifications.append(notification)
        super.post(notification)
    }
    
    override func post(name aName: NSNotification.Name, object anObject: Any?, userInfo aUserInfo: [AnyHashable: Any]? = nil) {
        let notification = Notification(name: aName, object: anObject, userInfo: aUserInfo)
        postedNotifications.append(notification)
        super.post(name: aName, object: anObject, userInfo: aUserInfo)
    }
}

final class DuckPlayerNativeUIPresenterTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: DuckPlayerNativeUIPresenter!
    private var mockHostViewController: MockDuckPlayerHostingViewControlling!
    private var mockAppSettings: AppSettingsMock!
    private var mockChromeDelegate: MockDuckPlayerChromeDelegate!
    private var mockPrivacyConfig: PrivacyConfigurationManagerMock!
    private var mockInternalUserDecider: MockDuckPlayerInternalUserDecider!
    private var cancellables: Set<AnyCancellable>!
    private var testNotificationCenter: TestNotificationCenter!
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        testNotificationCenter = TestNotificationCenter()
        mockHostViewController = MockDuckPlayerHostingViewControlling()
        mockChromeDelegate = MockDuckPlayerChromeDelegate()
        mockChromeDelegate.barsMaxHeight = 44.0 // Set a standard address bar height
        mockHostViewController.duckPlayerChromeDelegate = mockChromeDelegate
        
        // Initialize the web view constraint with a default value
        let constraint = NSLayoutConstraint()
        constraint.constant = 0
        mockHostViewController.webViewBottomAnchorConstraint = constraint
        
        mockAppSettings = AppSettingsMock()
        mockPrivacyConfig = PrivacyConfigurationManagerMock()
        mockInternalUserDecider = MockDuckPlayerInternalUserDecider()
        
        sut = DuckPlayerNativeUIPresenter(appSettings: mockAppSettings, notificationCenter: testNotificationCenter)
        cancellables = []
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
        
        // Test with top address bar position
        mockAppSettings.currentAddressBarPosition = .top
        
        // When
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        
        // Simulate sheet animation completion and visibility
        guard let containerViewModel = sut.containerViewModel else {
            XCTFail("Container view model should be created")
            return
        }
        containerViewModel.sheetAnimationCompleted = true
        //containerViewModel.sheetVisible = true
        
        // Then
        guard let pill = sut.hostView?.view else {
            XCTFail("Hostview not found")
            return
        }
        
        // Verify basic state
        XCTAssertEqual(pill.subviews.count, 1, "There must be only one subview (The pill)")
        XCTAssertEqual(sut.state.hasBeenShown, false, "DuckPlayer should not have been shown yet")
        XCTAssertEqual(sut.state.videoID, "kaajas891", "The video ID should be set")
        XCTAssertEqual(sut.state.timestamp, nil, "Entry pill should never have a timestamp")
        
        // Verify container view model
        XCTAssertTrue(containerViewModel.sheetVisible, "Container should be visible")
        
        // Verify container view controller
        guard let containerViewController = sut.containerViewController else {
            XCTFail("Container view controller should be created")
            return
        }
        XCTAssertEqual(containerViewController.view.backgroundColor, .clear, "Container should have clear background")
        XCTAssertFalse(containerViewController.view.isOpaque, "Container should not be opaque")
        XCTAssertEqual(containerViewController.modalPresentationStyle, .overCurrentContext, "Container should be presented over current context")
        XCTAssertFalse(containerViewController.view.translatesAutoresizingMaskIntoConstraints, "Container should not translate autoresizing mask")
        
        // Verify layout constraints
        guard let bottomConstraint = sut.bottomConstraint else {
            XCTFail("Bottom constraint should be set")
            return
        }
        XCTAssertEqual(bottomConstraint.firstItem as? UIView, containerViewController.view, "Bottom constraint should be attached to container view")
        XCTAssertEqual(bottomConstraint.secondItem as? UIView, mockHostViewController.view, "Bottom constraint should be attached to host view")
        
        // Verify web view constraint updates for top address bar
        let expectedTopBarConstraint = -DuckPlayerNativeUIPresenter.Constants.webViewRequiredBottomConstraint // -90
        XCTAssertEqual(mockHostViewController.webViewBottomAnchorConstraint?.constant, expectedTopBarConstraint, "Web view bottom constraint should be updated for pill height with top address bar")
        
        // Test with bottom address bar position
        mockAppSettings.currentAddressBarPosition = .bottom
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        
        // Simulate sheet animation completion and visibility for bottom address bar test
        containerViewModel.sheetAnimationCompleted = true
        //containerViewModel.sheetVisible = true
        
        // Verify web view constraint updates for bottom address bar
        // Expected value = -(barsMaxHeight + webViewRequiredBottomConstraint)
        // = -(44 + 90) = -134
        let expectedBottomBarConstraint = -(mockChromeDelegate.barsMaxHeight + DuckPlayerNativeUIPresenter.Constants.webViewRequiredBottomConstraint)
        XCTAssertEqual(mockHostViewController.webViewBottomAnchorConstraint?.constant, expectedBottomBarConstraint, "Web view bottom constraint should account for bottom address bar and pill height")
        
        // Verify notification posting
        let postedNotifications = testNotificationCenter.postedNotifications.filter { notification in
            notification.name == DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated
        }
        XCTAssertEqual(postedNotifications.count, 2, "Should post exactly two pill visibility notifications (one for each address bar position test)")
        
        let notification = postedNotifications.first
        XCTAssertNotNil(notification, "Should have posted a notification")
        XCTAssertEqual(notification?.name, DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated, "Should post the correct notification")
        XCTAssertEqual(notification?.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool, true, "Should indicate pill is visible")
    }

    @MainActor
    func testPresentDuckPlayer_PresentsView() {
        
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

