//
//  AuthenticationServiceTests.swift
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

import Foundation
import UIKit
import Testing
@testable import DuckDuckGo

final class MockPrivacyStore: PrivacyStore {

    var authenticationEnabled: Bool = true

}

final class MockAuthenticator: Authenticating {

    var authenticateCalled = false
    var isAuthenticationAvailable = true

    func canAuthenticate() -> Bool {
        isAuthenticationAvailable
    }
    
    func authenticate(reason: String) async -> Bool {
        authenticateCalled = true
        return true
    }

}

final class AuthenticationServiceTests {

    var authenticationService: AuthenticationService!
    var mockAuthenticator: MockAuthenticator!
    var mockOverlayWindowManager: MockOverlayWindowManager!
    var mockPrivacyStore: MockPrivacyStore!

    init() {
        mockAuthenticator = MockAuthenticator()
        mockOverlayWindowManager = MockOverlayWindowManager()
        mockPrivacyStore = MockPrivacyStore()
        authenticationService = AuthenticationService(authenticator: mockAuthenticator,
                                                      overlayWindowManager: mockOverlayWindowManager,
                                                      privacyStore: mockPrivacyStore)
    }

    @Test("authenticate() when authentication enabled removes overlay and displays AuthenticationScreen")
    func authenticate() async {
        // Given
        mockPrivacyStore.authenticationEnabled = true
        mockAuthenticator.isAuthenticationAvailable = true

        // When
        await authenticationService.authenticate()

        // Then
        #expect(mockOverlayWindowManager.removeOverlayCalled)
        #expect(mockOverlayWindowManager.displayOverlayCalled)
        #expect(mockAuthenticator.authenticateCalled)
        #expect(mockOverlayWindowManager.lastDisplayedViewController is AuthenticationViewController)
    }

    @Test("authenticate() when authentication disabled does nothing")
    func authenticateWithAuthenticationDisabled() async {
        // Given
        mockPrivacyStore.authenticationEnabled = false
        mockAuthenticator.isAuthenticationAvailable = true

        // When
        await authenticationService.authenticate()

        // Then
        #expect(!mockOverlayWindowManager.removeOverlayCalled)
        #expect(!mockOverlayWindowManager.displayOverlayCalled)
        #expect(!mockAuthenticator.authenticateCalled)
    }

    @Test("authenticate() when authentication not available does nothing")
    func authenticateWithAuthenticationNotAvailable() async {
        // Given
        mockPrivacyStore.authenticationEnabled = true
        mockAuthenticator.isAuthenticationAvailable = false

        // When
        await authenticationService.authenticate()

        // Then
        #expect(!mockOverlayWindowManager.removeOverlayCalled)
        #expect(!mockOverlayWindowManager.displayOverlayCalled)
        #expect(!mockAuthenticator.authenticateCalled)
    }

    @Test("suspend() when authentication enabled should display blank snapshot window")
    func suspend() {
        // Given
        mockPrivacyStore.authenticationEnabled = true

        // When
        authenticationService.suspend()

        // Then
        #expect(mockOverlayWindowManager.displayBlankSnapshotWindowCalled)
    }

    @Test("suspend() when authentication disabled does nothing")
    func suspendWithAuthenticationDisabled() {
        // Given
        mockPrivacyStore.authenticationEnabled = false

        // When
        authenticationService.suspend()

        // Then
        #expect(!mockOverlayWindowManager.displayBlankSnapshotWindowCalled)
    }

}

final class PrivacyUserDefaultsTests {

    @Test("Enabling authentication posts authentication-enabled-changed notification")
    func whenAuthenticationChangesFromDisabledToEnabledThenNotificationIsPosted() async throws {
        let suiteName = "PrivacyUserDefaultsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let privacyStore = PrivacyUserDefaults(userDefaults: userDefaults)
        #expect(!privacyStore.authenticationEnabled)

        await confirmation { notificationReceived in
            let observer = NotificationCenter.default.addObserver(
                forName: PrivacyUserDefaults.Notifications.authenticationEnabledChanged,
                object: nil,
                queue: nil) { notification in
                #expect(notification.object as? Bool == true)
                notificationReceived()
            }
            defer {
                NotificationCenter.default.removeObserver(observer)
            }

            privacyStore.authenticationEnabled = true
        }
    }
}
