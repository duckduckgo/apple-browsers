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
    var authenticationSucceeds = true
    var authenticationCallback: (() -> Void)?
    var authenticationResultProvider: (() async -> Bool)?

    func canAuthenticate() -> Bool {
        isAuthenticationAvailable
    }
    
    func authenticate(reason: String) async -> Bool {
        authenticateCalled = true
        let result = authenticationSucceeds
        authenticationCallback?()
        return await authenticationResultProvider?() ?? result
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

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test("A failed authentication holds the launch until retry succeeds or the wait is cancelled",
          .timeLimit(.minutes(1)), arguments: [false, true])
    func failedAuthenticationWaitsForSuccessfulRetry(cancelBeforeRetry: Bool) async throws {
        mockAuthenticator.authenticationSucceeds = false
        var waitingContinuation: AsyncStream<Void>.Continuation!
        let waiting = AsyncStream<Void> { waitingContinuation = $0 }
        mockAuthenticator.authenticationCallback = { waitingContinuation.yield(()) }
        var completed = false
        let task = Task { @MainActor in
            await authenticationService.authenticate(waitForSuccessfulAuthentication: true)
            completed = true
        }
        var iterator = waiting.makeAsyncIterator()
        await iterator.next()
        let lockScreen = try #require(mockOverlayWindowManager.lastDisplayedViewController as? AuthenticationViewController)
        mockOverlayWindowManager.removeOverlayCalled = false
        #expect(!completed)
        #expect(!authenticationService.hasCompletedAuthentication)

        if cancelBeforeRetry {
            task.cancel()
        } else {
            mockAuthenticator.authenticationSucceeds = true
            authenticationService.authenticationViewController(authenticationViewController: lockScreen, didTapWithSender: lockScreen)
        }
        await task.value
        #expect(completed)
        #expect(mockOverlayWindowManager.removeOverlayCalled == !cancelBeforeRetry)
        #expect(authenticationService.hasCompletedAuthentication == !cancelBeforeRetry)
    }

    @available(iOS 16, macOS 13, *)
    @MainActor
    @Test("A flag-on authentication success arriving after suspend cannot remove the lock overlay", .timeLimit(.minutes(1)))
    func lateAuthenticationSuccessAfterSuspendKeepsLock() async {
        var startedContinuation: AsyncStream<Void>.Continuation!
        let started = AsyncStream<Void> { startedContinuation = $0 }
        var resultContinuation: AsyncStream<Bool>.Continuation!
        let result = AsyncStream<Bool> { resultContinuation = $0 }
        mockAuthenticator.authenticationCallback = { startedContinuation.yield(()) }
        mockAuthenticator.authenticationResultProvider = {
            var iterator = result.makeAsyncIterator()
            return await iterator.next() ?? false
        }
        let task = Task { @MainActor in
            await authenticationService.authenticate(waitForSuccessfulAuthentication: true)
        }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        mockOverlayWindowManager.removeOverlayCalled = false
        // Do not cancel this task: retry tasks are independent of the cancelled launch task.
        authenticationService.suspend()
        resultContinuation.yield(true)
        resultContinuation.finish()
        await task.value
        #expect(!mockOverlayWindowManager.removeOverlayCalled)
        #expect(mockOverlayWindowManager.displayBlankSnapshotWindowCalled)
        #expect(!authenticationService.hasCompletedAuthentication)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off authentication still returns after a failed attempt", .timeLimit(.minutes(1)))
    func flagOffReturnsAfterFailedAuthentication() async {
        mockAuthenticator.authenticationSucceeds = false
        await authenticationService.authenticate(waitForSuccessfulAuthentication: false)
        #expect(mockAuthenticator.authenticateCalled)
        #expect(mockOverlayWindowManager.lastDisplayedViewController is AuthenticationViewController)
        #expect(!authenticationService.hasCompletedAuthentication)
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
        #expect(authenticationService.hasCompletedAuthentication)
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
        #expect(authenticationService.hasCompletedAuthentication)
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
        #expect(authenticationService.hasCompletedAuthentication)
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
