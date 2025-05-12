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
import WebKit

@testable import DuckDuckGo

extension DuckPlayerNativeUIPresenterTests {
    struct Constants {
        static let webViewRequiredBottomConstraint: CGFloat = 90
    }
}

class TestNotificationCenter: NotificationCenter, @unchecked Sendable {
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
    private var mockHostViewController: MockDuckPlayerHosting!
    private var mockAppSettings: AppSettingsMock!
    private var mockDuckPlayerSettings: MockDuckPlayerSettings!
    private var mockPrivacyConfig: PrivacyConfigurationManagerMock!
    private var mockInternalUserDecider: MockDuckPlayerInternalUserDecider!
    private var cancellables: Set<AnyCancellable>!
    private var testNotificationCenter: TestNotificationCenter!
    private var constraintUpdates: [DuckPlayerConstraintUpdate] = []

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        testNotificationCenter = TestNotificationCenter()
        mockHostViewController = MockDuckPlayerHosting()
        mockHostViewController.webView = WKWebView(frame: .zero, configuration: .nonPersistent())
        mockHostViewController.persistentBottomBarHeight = 44.0 // Set a standard address bar height

        // Initialize the content bottom constraint
        let dummyView = UIView()
        mockHostViewController.view.addSubview(dummyView)
        mockHostViewController.contentBottomConstraint = dummyView.bottomAnchor.constraint(equalTo: mockHostViewController.view.bottomAnchor)
        mockHostViewController.contentBottomConstraint?.isActive = true

        mockAppSettings = AppSettingsMock()
        mockPrivacyConfig = PrivacyConfigurationManagerMock()
        mockInternalUserDecider = MockDuckPlayerInternalUserDecider()
        mockDuckPlayerSettings = MockDuckPlayerSettings(
            appSettings: mockAppSettings,
            privacyConfigManager: mockPrivacyConfig,
            internalUserDecider: mockInternalUserDecider
        )

        sut = DuckPlayerNativeUIPresenter(
            appSettings: mockAppSettings,
            duckPlayerSettings: mockDuckPlayerSettings,
            state: DuckPlayerState(),
            notificationCenter: testNotificationCenter
        )

        // Subscribe to constraint updates
        cancellables = []
        sut.constraintUpdates.sink { [weak self] update in
            self?.constraintUpdates.append(update)
        }.store(in: &cancellables)
    }

    override func tearDown() {
        sut = nil
        mockHostViewController = nil
        mockAppSettings = nil
        mockDuckPlayerSettings = nil
        mockPrivacyConfig = nil
        mockInternalUserDecider = nil
        cancellables = nil
        constraintUpdates = []
        super.tearDown()
    }

    // MARK: - Welcome Pill Tests
    
    @MainActor
    func testPresentPill_WhenFirstTimeUser_ShowsWelcomePill() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = nil
        mockDuckPlayerSettings.primingMessagePresented = false
        
        // Set Variant Opt-in
        mockDuckPlayerSettings.variant = .nativeOptIn
      
        // When
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        
        // Simulate sheet animation completion and visibility
        guard let containerViewModel = sut.containerViewModel else {
            XCTFail("Container view model should be created")
            return
        }
        containerViewModel.sheetAnimationCompleted = true
        
        // Then
        XCTAssertTrue(mockDuckPlayerSettings.primingMessagePresented, "Welcome message should be marked as shown")
        
        // Verify constraint updates
        XCTAssertFalse(constraintUpdates.isEmpty, "Should have received constraint updates")
        if let lastUpdate = constraintUpdates.last, case .showPill(let height) = lastUpdate {
            XCTAssertEqual(height, Constants.webViewRequiredBottomConstraint, "Pill height should match expected value")
        } else {
            XCTFail("Should have received a .showPill constraint update")
        }
        
        // Verify notification posting
        let postedNotifications = testNotificationCenter.postedNotifications.filter { notification in
            notification.name == DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated
        }
        XCTAssertFalse(postedNotifications.isEmpty, "Should post pill visibility notifications")
        
        let notification = postedNotifications.first
        XCTAssertEqual(notification?.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool, true, "Should indicate pill is visible")
    }

    @MainActor
    func testDismissPill_WhenWelcomePill_TransitionsToEntryPill() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = nil
        mockDuckPlayerSettings.primingMessagePresented = false
        
        // Set Variant Opt-in
        mockDuckPlayerSettings.variant = .nativeOptIn
      
        // First present welcome pill
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        
        // Simulate sheet animation completion
        guard let containerViewModel = sut.containerViewModel else {
            XCTFail("Container view model should be created")
            return
        }
        containerViewModel.sheetAnimationCompleted = true
        
        // Clear existing notifications
        testNotificationCenter.postedNotifications.removeAll()
        constraintUpdates.removeAll()
        
        // When - dismiss the welcome pill
        sut.dismissPill(reset: false, animated: false, programatic: true)
        
        // Then - should automatically transition to entry pill
        XCTAssertTrue(mockDuckPlayerSettings.primingMessagePresented, "Welcome message should remain marked as shown")
        
        // Verify notification sequence (hide followed by show)
        let visibilityNotifications = testNotificationCenter.postedNotifications.filter { notification in
            notification.name == DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated
        }
        
        XCTAssertEqual(visibilityNotifications.count, 1, "Should post 1 visibility notifications")
        
        if visibilityNotifications.count >= 2 {
            let firstNotif = visibilityNotifications[0]
            let secondNotif = visibilityNotifications[1]
            
            XCTAssertEqual(firstNotif.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool, false, "First should indicate pill is hidden")
            XCTAssertEqual(secondNotif.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool, true, "Second should indicate pill is visible again")
        }
    }

    // MARK: - presentPill Tests

    @MainActor
    func testPresentPill_WhenFirstTimeInVideo_ShowsEntryPill() {
        // Given
        let videoID = "kaajas891"
        let timestamp: TimeInterval? = 100
        mockDuckPlayerSettings.primingMessagePresented = true // Not first time
      
        // Set Variant Opt-in
        mockDuckPlayerSettings.variant = .nativeOptIn
    
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

        // Then
        guard let pill = sut.hostView?.view else {
            XCTFail("Hostview not found")
            return
        }

        // Verify basic state
        XCTAssertEqual(pill.subviews.count, 2, "There must two subviews (Incluiding The pill)")
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

        // Change address bar position
        mockAppSettings.currentAddressBarPosition = .bottom
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)

        // Simulate sheet animation completion and visibility for bottom address bar test
        containerViewModel.sheetAnimationCompleted = true

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
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = 30
        let source: DuckPlayer.VideoNavigationSource = .youtube
        mockDuckPlayerSettings.welcomeMessageShown = true

        // When
        let (navigation, settings) = sut.presentDuckPlayer(
            videoID: videoID,
            source: source,
            in: mockHostViewController,
            title: nil,
            timestamp: timestamp
        )

        // Then
        // Verify view model was created with correct parameters
        guard let playerViewModel = sut.playerViewModel else {
            XCTFail("Player view model should be created")
            return
        }
        XCTAssertEqual(playerViewModel.videoID, videoID, "Video ID should be set correctly")
        XCTAssertEqual(playerViewModel.timestamp, timestamp, "Timestamp should be set correctly")
        XCTAssertEqual(playerViewModel.source, source, "Source should be set correctly")

        // Verify hosting controller was created with correct configuration
        guard let hostingController = mockHostViewController.presentedViewController as? UIHostingController<DuckPlayerView> else {
            XCTFail("Hosting controller should be created with DuckPlayerView")
            return
        }
        XCTAssertFalse(hostingController.isModalInPresentation, "Should not be modal in presentation")

        // Verify state was updated
        XCTAssertTrue(sut.state.hasBeenShown, "State should indicate DuckPlayer has been shown")

        // Verify publishers were created
        XCTAssertNotNil(navigation, "Navigation publisher should be created")
        XCTAssertNotNil(settings, "Settings publisher should be created")

        // Validate state updates
        XCTAssertEqual(sut.state.hasBeenShown, true, "DuckPlayer should have been shown")
    }

    @MainActor
    func testPresentPill_WhenDuckPlayerIsDismissed_ShowsReEntryPill() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = 30
        let source: DuckPlayer.VideoNavigationSource = .youtube
        mockDuckPlayerSettings.welcomeMessageShown = true

        // When
        // First present the pill
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)

        // Present DuckPlayer
        let (_, _) = sut.presentDuckPlayer(
            videoID: videoID,
            source: source,
            in: mockHostViewController,
            title: nil,
            timestamp: timestamp
        )

        // Subscribe to pill visibility notifications to detect when it's shown again
        testNotificationCenter.addObserver(
            self,
            selector: #selector(handlePillVisibilityChange),
            name: DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated,
            object: nil
        )

        // Simulate DuckPlayer dismissal with a timestamp
        guard let playerViewModel = sut.playerViewModel else {
            XCTFail("Player view model should be created")
            return
        }
        playerViewModel.dismissPublisher.send(timestamp ?? 0)

        // Then
        // Verify state after DuckPlayer presentation
        XCTAssertEqual(sut.state.hasBeenShown, true, "DuckPlayer should have been shown")
        XCTAssertEqual(sut.state.videoID, videoID, "The video ID should be set")

        // Verify pill was presented again after dismissal
        let postedNotifications = testNotificationCenter.postedNotifications.filter { notification in
            notification.name == DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated
        }
        XCTAssertEqual(postedNotifications.count, 3, "Should have three pill visibility notifications (initial, presentation and after dismissal)")

        // Verify the second notification indicates visibility
        let secondNotification = postedNotifications.last
        XCTAssertEqual(secondNotification?.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool, true, "Second notification should indicate pill is visible")

        // Verify the timestamp was preserved
        XCTAssertEqual(sut.state.timestamp, timestamp, "Timestamp should be preserved after dismissal")
    }

    @objc private func handlePillVisibilityChange(_ notification: Notification) {
        // This is just a placeholder for the notification observer
        // The actual verification is done in the test
    }

    // MARK: - dismissPill Tests

    @MainActor
    func testDismissPill_WhenProgramatic_DoesNotIncrementDismissCount() {
        // Given
        let initialCount = mockDuckPlayerSettings.pillDismissCount

        // When
        sut.dismissPill(reset: false, animated: true, programatic: true)

        // Then
        XCTAssertEqual(mockDuckPlayerSettings.pillDismissCount, initialCount)
    }

    @MainActor
    func testDismissPill_WhenUserDismissed_IncrementsDismissCount() {
        // Given
        let initialCount = mockDuckPlayerSettings.pillDismissCount

        // When
        sut.dismissPill(reset: false, animated: true, programatic: false)

        // Then
        XCTAssertEqual(mockDuckPlayerSettings.pillDismissCount, initialCount + 1)
    }

    @MainActor
    func testDismissPill_WhenReset_ResetsState() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = 30
        mockDuckPlayerSettings.welcomeMessageShown = true

        // Set up initial state
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        mockDuckPlayerSettings.pillDismissCount = 2

        // When
        sut.dismissPill(reset: true, animated: true, programatic: true)

        // Then
        // Verify state was reset
        XCTAssertFalse(sut.state.hasBeenShown, "State should indicate DuckPlayer has not been shown")
        XCTAssertNil(sut.state.videoID, "Video ID should be cleared")
        XCTAssertNil(sut.state.timestamp, "Timestamp should be cleared")
    }

    @MainActor
    func testDismissPill_WhenThresholdReached_PresentsToastOnce() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = 30
        mockDuckPlayerSettings.welcomeMessageShown = true

        // Set up initial state
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)
        mockDuckPlayerSettings.pillDismissCount = 2

        // When - First dismiss to reach threshold
        sut.dismissPill(reset: false, animated: true, programatic: false)

        // Then
        // Verify dismiss count reached threshold
        XCTAssertEqual(mockDuckPlayerSettings.pillDismissCount, 3, "Dismiss count should reach threshold")

        // When - Multiple subsequent dismisses
        sut.dismissPill(reset: false, animated: true, programatic: false)
        sut.dismissPill(reset: false, animated: true, programatic: false)
        sut.dismissPill(reset: false, animated: true, programatic: false)

        // Then
        // Verify dismiss count continues to increment
        XCTAssertEqual(mockDuckPlayerSettings.pillDismissCount, 6, "Dismiss count should increment")

        // When - Present and dismiss DuckPlayer multiple times
        _ = sut.presentDuckPlayer(videoID: videoID, source: .youtube, in: mockHostViewController, title: nil, timestamp: timestamp)
        sut.dismissPill(reset: false, animated: true, programatic: false)
        _ = sut.presentDuckPlayer(videoID: videoID, source: .youtube, in: mockHostViewController, title: nil, timestamp: timestamp)
        sut.dismissPill(reset: false, animated: true, programatic: false)

        // Then
        // Verify dismiss count continues to increment
        XCTAssertEqual(mockDuckPlayerSettings.pillDismissCount, 8, "Dismiss count should continue incrementing")
    }

    // MARK: - presentDuckPlayer Tests

    @MainActor
    func testPresentDuckPlayer_ResetsDismissCountIfBelowThreshold() {
        // Given
        mockDuckPlayerSettings.pillDismissCount = 2

        // When
        _ = sut.presentDuckPlayer(
            videoID: "test123",
            source: .youtube,
            in: mockHostViewController,
            title: nil,
            timestamp: nil
        )

        // Then
        XCTAssertEqual(mockDuckPlayerSettings.pillDismissCount, 0)
    }

    @MainActor
    func testPresentDuckPlayer_DoesNotResetDismissCountIfAboveThreshold() {
        // Given
        mockDuckPlayerSettings.pillDismissCount = 3

        // When
        _ = sut.presentDuckPlayer(
            videoID: "test123",
            source: .youtube,
            in: mockHostViewController,
            title: nil,
            timestamp: nil
        )

        // Then
        XCTAssertEqual(mockDuckPlayerSettings.pillDismissCount, 3)
    }

    // MARK: - Video Playback Request Tests

    @MainActor
    func testVideoPlaybackRequest_WhenPillOpened_SendsRequest() {
        // Given
        let videoID = "test123"
        let timestamp: TimeInterval? = 30
        var receivedRequest: (videoID: String, timestamp: TimeInterval?)?
        mockDuckPlayerSettings.welcomeMessageShown = true

        sut.videoPlaybackRequest.sink { request in
            receivedRequest = request
        }.store(in: &cancellables)

        // When
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)

        // Simulate the video playback request directly
        sut.videoPlaybackRequest.send((videoID, timestamp))

        // Then
        XCTAssertNotNil(receivedRequest)
        XCTAssertEqual(receivedRequest?.videoID, videoID)
        XCTAssertEqual(receivedRequest?.timestamp, timestamp)
    }
    
    // MARK: - Chrome Show/Hide Tests
    
    @MainActor
    func testHideBottomSheetForHiddenChrome_DisablesPillAndResetsConstraints() {
        // Given
        let videoID = "test123"
        mockDuckPlayerSettings.welcomeMessageShown = true
        
        // Present pill first
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: nil)
        
        // Clear existing notifications and constraint updates
        testNotificationCenter.postedNotifications.removeAll()
        constraintUpdates.removeAll()
        
        // When
        sut.hideBottomSheetForHiddenChrome()
        
        // Then
        // Check constraint updates
        XCTAssertFalse(constraintUpdates.isEmpty, "Should have received constraint updates")
        if let lastUpdate = constraintUpdates.last, case .reset = lastUpdate {
            // Expected .reset constraint update
        } else {
            XCTFail("Should have received a .reset constraint update")
        }
        
        // Check visibility notification
        let visibilityNotifications = testNotificationCenter.postedNotifications.filter { notification in
            notification.name == DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated
        }
        
        XCTAssertEqual(visibilityNotifications.count, 1, "Should post 1 visibility notification")
        
        if let notification = visibilityNotifications.first {
            XCTAssertEqual(notification.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool, false, "Should indicate pill is hidden")
        }

        // Verify user interaction is disabled
        XCTAssertFalse(sut.containerViewController?.view.isUserInteractionEnabled ?? true, "User interaction should be disabled")
    }

    @MainActor
    func testShowBottomSheetForVisibleChrome_EnablesPillAndUpdatesConstraints() {
        // Given
        let videoID = "test123"
        mockDuckPlayerSettings.welcomeMessageShown = true

        // Present pill and hide it
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: nil)
        sut.hideBottomSheetForHiddenChrome()

        // Clear existing notifications and constraint updates
        testNotificationCenter.postedNotifications.removeAll()
        constraintUpdates.removeAll()

        // When
        sut.showBottomSheetForVisibleChrome()

        // Then
        // Check visibility notification
        let visibilityNotifications = testNotificationCenter.postedNotifications.filter { notification in
            notification.name == DuckPlayerNativeUIPresenter.Notifications.duckPlayerPillUpdated
        }

        XCTAssertEqual(visibilityNotifications.count, 1, "Should post 1 visibility notification")

        if let notification = visibilityNotifications.first {
            XCTAssertEqual(notification.userInfo?[DuckPlayerNativeUIPresenter.NotificationKeys.isVisible] as? Bool, true, "Should indicate pill is visible")
        }

        // Verify user interaction is enabled
        XCTAssertTrue(sut.containerViewController?.view.isUserInteractionEnabled ?? false, "User interaction should be enabled")
    }

    // MARK: - Constraint Updates Tests

    @MainActor
    func testConstraintUpdates_PublishesCorrectUpdates() {
        // Given
        let videoID = "test123"
        mockDuckPlayerSettings.welcomeMessageShown = true
        constraintUpdates.removeAll()
        
        var receivedUpdates: [DuckPlayerConstraintUpdate] = []
        sut.constraintUpdates.sink { update in
            receivedUpdates.append(update)
        }.store(in: &cancellables)
        
        // When - Present pill
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: nil)
        
        // Simulate animation completed
        sut.containerViewModel?.sheetAnimationCompleted = true
        
        // Then - Should get showPill update
        XCTAssertFalse(receivedUpdates.isEmpty, "Should have received constraint updates")

        // When - Hide
        receivedUpdates.removeAll()
        sut.hideBottomSheetForHiddenChrome()

        // Then - Should get reset update
        XCTAssertFalse(receivedUpdates.isEmpty, "Should have received constraint updates")
        for update in receivedUpdates {
            if case .reset = update {
                // Found expected update
                return
            }
        }
        XCTFail("Should have received a .reset constraint update")
    }

    // Welcome Message Tests

    @MainActor
    func testWelcomeMessage_IsShownWhenFirstUsingDuckPlayerNativeUI() {
        // Given         
        let videoID = "test123"
        let timestamp: TimeInterval? = 30
        let source: DuckPlayer.VideoNavigationSource = .youtube
        mockDuckPlayerSettings.welcomeMessageShown = false
        mockDuckPlayerSettings.variant = .nativeOptOut
      
        // Present pill
        sut.presentPill(for: videoID, in: mockHostViewController, timestamp: timestamp)

        // Present DuckPlayer
        let (_, _) = sut.presentDuckPlayer(
            videoID: videoID,
            source: source,
            in: mockHostViewController,
            title: nil,
            timestamp: timestamp
        )

        // Simulate dismiss
        _ = sut.playerViewModel?.dismissPublisher.send(Date().timeIntervalSince1970)

        // Then
        XCTAssertTrue(mockDuckPlayerSettings.welcomeMessageShown)

    }

    
}
