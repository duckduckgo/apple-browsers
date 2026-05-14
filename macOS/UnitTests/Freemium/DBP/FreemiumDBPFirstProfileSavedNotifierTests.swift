//
//  FreemiumDBPFirstProfileSavedNotifierTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class FreemiumDBPFirstProfileSavedNotifierTests: XCTestCase {

    private var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!
    private var subscriptionAuthenticationStateProvider: MockSubscriptionAuthenticationStateProvider!
    private var mockNotificationCenter: MockNotificationCenter!
    private var sut: FreemiumDBPFirstProfileSavedNotifier!

    override func setUpWithError() throws {
        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        subscriptionAuthenticationStateProvider = MockSubscriptionAuthenticationStateProvider()
        mockNotificationCenter = MockNotificationCenter()
        sut = FreemiumDBPFirstProfileSavedNotifier(freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
                                                   authenticationStateProvider: subscriptionAuthenticationStateProvider,
                                                   notificationCenter: mockNotificationCenter)
    }

    override func tearDown() {
        subscriptionAuthenticationStateProvider = nil
        mockFreemiumDBPUserStateManager = nil
        mockNotificationCenter = nil
        sut = nil
    }

    func testWhenAllCriteriaSatisfied_thenNotificationShouldBePosted() {
        // Given
        subscriptionAuthenticationStateProvider.isUserAuthenticated = false
        mockFreemiumDBPUserStateManager.didActivate = true
        mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification = false

        // When
        sut.postProfileSavedNotificationIfPermitted()

        // Then
        XCTAssertTrue(mockNotificationCenter.didCallPostNotification)
        XCTAssertEqual(mockNotificationCenter.lastPostedNotification, .pirProfileSaved)
        XCTAssertTrue(mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification)
    }

    func testWhenUserIsAuthenticated_thenNotificationShouldNotBePosted() {
        // Given
        subscriptionAuthenticationStateProvider.isUserAuthenticated = true
        mockFreemiumDBPUserStateManager.didActivate = true
        mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification = false

        // When
        sut.postProfileSavedNotificationIfPermitted()

        // Then
        XCTAssertFalse(mockNotificationCenter.didCallPostNotification)
    }

    func testWhenUserHasNotActivated_thenNotificationShouldNotBePosted() {
        // Given
        subscriptionAuthenticationStateProvider.isUserAuthenticated = false
        mockFreemiumDBPUserStateManager.didActivate = false
        mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification = false

        // When
        sut.postProfileSavedNotificationIfPermitted()

        // Then
        XCTAssertFalse(mockNotificationCenter.didCallPostNotification)
    }

    func testWhenNotificationAlreadyPosted_thenShouldNotPostAgain() {
        // Given
        subscriptionAuthenticationStateProvider.isUserAuthenticated = false
        mockFreemiumDBPUserStateManager.didActivate = true
        mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification = true

        // When
        sut.postProfileSavedNotificationIfPermitted()

        // Then
        XCTAssertFalse(mockNotificationCenter.didCallPostNotification)
    }

    func testWhenNotificationIsPosted_thenStateShouldBeUpdated() {
        // Given
        subscriptionAuthenticationStateProvider.isUserAuthenticated = false
        mockFreemiumDBPUserStateManager.didActivate = true
        mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification = false

        // When
        sut.postProfileSavedNotificationIfPermitted()

        // Then
        XCTAssertTrue(mockNotificationCenter.didCallPostNotification)
        XCTAssertEqual(mockNotificationCenter.lastPostedNotification, .pirProfileSaved)
        XCTAssertTrue(mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification)
    }
}
