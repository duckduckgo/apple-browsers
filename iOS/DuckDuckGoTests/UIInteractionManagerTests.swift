//
//  UIInteractionManagerTests.swift
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

import UIKit
import Testing
@testable import DuckDuckGo

final class MockAuthenticationService: AuthenticationServiceProtocol {

    var authenticateCalled = false
    var waitUntilUnlockedCallback: (() async -> Void)?

    func authenticate(waitForSuccessfulAuthentication: Bool) async {
        authenticateCalled = true
        if waitForSuccessfulAuthentication {
            await waitUntilUnlockedCallback?()
        }
    }

}

final class MockAutoClearService: AutoClearServiceProtocol {

    var isClearingEnabled: Bool = true
    var isTabClearingEnabled: Bool = true
    var autoClearTask: Task<Void, Never>?

    var waitForDataClearedCalled = false
    var clearDataCallback: (() async -> Void)?

    func waitForDataCleared() async {
        waitForDataClearedCalled = true
        await clearDataCallback?()
    }

}

final class MockLaunchActionHandler: LaunchActionHandling {

    var handleLaunchActionCalled = false
    var lastHandledLaunchAction: LaunchAction?

    func handleLaunchAction(_ action: LaunchAction) {
        handleLaunchActionCalled = true
        lastHandledLaunchAction = action
    }

}

final class MockOnboardingPresenting: OnboardingPresenting {
    private(set) var didCallPresentOnboarding = false
    private(set) var capturedURL: URL?

    func startOnboardingFlowIfNotSeenBefore(url: URL?) {
        didCallPresentOnboarding = true
        capturedURL = url
    }
}

@MainActor
final class UIInteractionManagerTests {

    let mockAuthService = MockAuthenticationService()
    let mockAutoClearService = MockAutoClearService()
    let mockLaunchActionHandler = MockLaunchActionHandler()
    let mockOnboardingPresenter = MockOnboardingPresenting()
    lazy var uiInteractionManager = UIInteractionManager(
        authenticationService: mockAuthService,
        autoClearService: mockAutoClearService,
        launchActionHandler: mockLaunchActionHandler,
        onboardingPresenter: mockOnboardingPresenter
    )

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling before a flag-on launch starts performs no authentication or callbacks", .timeLimit(.minutes(1)))
    func cancellationBeforeStartDoesNotAuthenticate() async {
        let sut = UIInteractionManager(authenticationService: mockAuthService,
                                       autoClearService: mockAutoClearService,
                                       launchActionHandler: mockLaunchActionHandler,
                                       onboardingPresenter: mockOnboardingPresenter,
                                       waitsForSuccessfulAuthentication: true,
                                       isApplicationActive: { true })
        let task = sut.start(launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true),
                             onWebViewReadyForInteractions: { Issue.record("Cancelled launch called web-view readiness") },
                             onAppReadyForInteractions: { Issue.record("Cancelled launch called app readiness") })
        sut.cancelPendingInteractions()
        await task.value
        #expect(!mockAuthService.authenticateCalled)
        #expect(!mockAutoClearService.waitForDataClearedCalled)
        #expect(!mockLaunchActionHandler.handleLaunchActionCalled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-on launch waits for unlock and cancels on background", .timeLimit(.minutes(1)), arguments: [false, true])
    func waitsForUnlockUnlessCancelled(cancelBeforeUnlock: Bool) async {
        var waitStartedContinuation: AsyncStream<Void>.Continuation!
        let waitStarted = AsyncStream<Void> { waitStartedContinuation = $0 }
        var unlockedContinuation: AsyncStream<Void>.Continuation!
        let unlocked = AsyncStream<Void> { unlockedContinuation = $0 }
        mockAuthService.waitUntilUnlockedCallback = {
            waitStartedContinuation.yield(())
            for await _ in unlocked { }
        }
        let sut = UIInteractionManager(authenticationService: mockAuthService,
                                       autoClearService: mockAutoClearService,
                                       launchActionHandler: mockLaunchActionHandler,
                                       onboardingPresenter: mockOnboardingPresenter,
                                       waitsForSuccessfulAuthentication: true,
                                       isApplicationActive: { true })
        var appReady = false
        let task = sut.start(launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true),
                             onWebViewReadyForInteractions: { },
                             onAppReadyForInteractions: { appReady = true })
        var iterator = waitStarted.makeAsyncIterator()
        await iterator.next()
        #expect(!mockLaunchActionHandler.handleLaunchActionCalled)
        #expect(!appReady)

        if cancelBeforeUnlock {
            sut.cancelPendingInteractions()
            // Completion before any unlock proves the cancelled stream does not keep the launch alive.
            await task.value
            unlockedContinuation.finish()
        } else {
            unlockedContinuation.finish()
            await task.value
        }
        #expect(mockLaunchActionHandler.handleLaunchActionCalled == !cancelBeforeUnlock)
        #expect(appReady == !cancelBeforeUnlock)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off launch keeps the first authentication attempt behavior without waiting for activation", .timeLimit(.minutes(1)))
    func flagOffDoesNotWaitForUnlock() async {
        mockAuthService.waitUntilUnlockedCallback = { Issue.record("Legacy launch must not wait for successful authentication") }
        let sut = UIInteractionManager(authenticationService: mockAuthService,
                                       autoClearService: mockAutoClearService,
                                       launchActionHandler: mockLaunchActionHandler,
                                       onboardingPresenter: mockOnboardingPresenter,
                                       waitsForSuccessfulAuthentication: false,
                                       isApplicationActive: { false })
        var appReady = false
        let task = sut.start(launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true),
                             onWebViewReadyForInteractions: { },
                             onAppReadyForInteractions: { appReady = true })
        await task.value
        #expect(mockLaunchActionHandler.handleLaunchActionCalled)
        #expect(appReady)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Successful authentication waits for activation and cancels on background", .timeLimit(.minutes(1)), arguments: [false, true])
    func waitsForActivationUnlessCancelled(cancelBeforeActivation: Bool) async {
        let notificationCenter = NotificationCenter()
        var isApplicationActive = false
        var stateChecks = 0
        var waitingContinuation: AsyncStream<Void>.Continuation!
        let waiting = AsyncStream<Void> { waitingContinuation = $0 }
        let sut = UIInteractionManager(authenticationService: mockAuthService,
                                       autoClearService: mockAutoClearService,
                                       launchActionHandler: mockLaunchActionHandler,
                                       onboardingPresenter: mockOnboardingPresenter,
                                       waitsForSuccessfulAuthentication: true,
                                       notificationCenter: notificationCenter,
                                       isApplicationActive: {
                                           stateChecks += 1
                                           // The second check follows notification registration.
                                           if stateChecks == 2 { waitingContinuation.yield(()) }
                                           return isApplicationActive
                                       })
        var appReady = false
        let task = sut.start(launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true),
                             onWebViewReadyForInteractions: { },
                             onAppReadyForInteractions: { appReady = true })
        var iterator = waiting.makeAsyncIterator()
        await iterator.next()
        #expect(mockAuthService.authenticateCalled)
        #expect(!mockLaunchActionHandler.handleLaunchActionCalled)
        #expect(!appReady)

        if cancelBeforeActivation {
            sut.cancelPendingInteractions()
            await task.value
        }
        isApplicationActive = true
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await task.value

        #expect(mockLaunchActionHandler.handleLaunchActionCalled == !cancelBeforeActivation)
        #expect(appReady == !cancelBeforeActivation)
    }

    @Test("Start method calls onWebViewReadyForInteractions and opens URL")
    func startCallsOnWebViewReadyForInteractionsAndOpensURL() async {
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .openURL(URL("www.duckduckgo.com")!),
                onWebViewReadyForInteractions: {
                    #expect(self.mockAutoClearService.waitForDataClearedCalled)
                    #expect(self.mockLaunchActionHandler.handleLaunchActionCalled)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

    @Test("Start method calls onWebViewReadyForInteractions and does not show keyboard unless authentication happened")
    func startCallsOnWebViewReadyForInteractionsAndDoesNotShowKeyboard() async {
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false),
                onWebViewReadyForInteractions: {
                    #expect(self.mockAutoClearService.waitForDataClearedCalled)
                    #expect(!self.mockLaunchActionHandler.handleLaunchActionCalled)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

    @Test("Start method calls onAppReadyForInteractions")
    func startCallsOnAppReadyForInteractions() async {
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false),
                onWebViewReadyForInteractions: {
                    #expect(!self.mockLaunchActionHandler.handleLaunchActionCalled)
                },
                onAppReadyForInteractions: {
                    #expect(self.mockAutoClearService.waitForDataClearedCalled)
                    #expect(self.mockAuthService.authenticateCalled)
                    #expect(self.mockLaunchActionHandler.handleLaunchActionCalled)
                    continuation.resume()
                }
            )
        }
    }

    @Test("Start method presents onboarding with nil URL for standard launch")
    func startPresentsOnboardingWithNilURLForStandardLaunch() async {
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true),
                onWebViewReadyForInteractions: {
                    #expect(self.mockOnboardingPresenter.didCallPresentOnboarding)
                    #expect(self.mockOnboardingPresenter.capturedURL == nil)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

    @Test("Start method presents onboarding with nil URL for shortcut item")
    func startPresentsOnboardingWithNilURLForShortcutItem() async {
        let shortcutItem = UIApplicationShortcutItem(type: "test", localizedTitle: "Test")
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .handleShortcutItem(shortcutItem),
                onWebViewReadyForInteractions: {
                    #expect(self.mockOnboardingPresenter.didCallPresentOnboarding)
                    #expect(self.mockOnboardingPresenter.capturedURL == nil)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

    @Test("Start method presents onboarding with nil URL for user activity")
    func startPresentsOnboardingWithNilURLForUserActivity() async {
        let userActivity = NSUserActivity(activityType: "test")
        await withCheckedContinuation { continuation in
            uiInteractionManager.start(
                launchAction: .handleUserActivity(userActivity),
                onWebViewReadyForInteractions: {
                    #expect(self.mockOnboardingPresenter.didCallPresentOnboarding)
                    #expect(self.mockOnboardingPresenter.capturedURL == nil)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

    @Test("Start method presents onboarding before handling immediate launch actions")
    func startPresentsOnboardingBeforeHandlingImmediateLaunchActions() async {
        // Override the onboarding coordinator to track order of operations
        final class MockOnboardingPresenter: OnboardingPresenting {
            private(set) var didCallPresentOnboarding = false
            private(set) var didPresentOnboardingBeforeHandlingActions: Bool = false

            private let launchActionHandler: MockLaunchActionHandler

            init(launchActionHandler: MockLaunchActionHandler) {
                self.launchActionHandler = launchActionHandler
            }

            func startOnboardingFlowIfNotSeenBefore(url: URL?) {
                didCallPresentOnboarding = true
                // Check if launch action was already called
                didPresentOnboardingBeforeHandlingActions = !launchActionHandler.handleLaunchActionCalled
            }
        }

        let url = URL(string: "https://example.com")!
        let mockLaunchActionHandler = MockLaunchActionHandler()
        let mockOnboardingPresenter = MockOnboardingPresenter(launchActionHandler: mockLaunchActionHandler)

        let sut = UIInteractionManager(
            authenticationService: mockAuthService,
            autoClearService: mockAutoClearService,
            launchActionHandler: mockLaunchActionHandler,
            onboardingPresenter: mockOnboardingPresenter
        )

        await withCheckedContinuation { continuation in
            sut.start(
                launchAction: .openURL(url),
                onWebViewReadyForInteractions: {
                    #expect(mockOnboardingPresenter.didCallPresentOnboarding)
                    #expect(mockOnboardingPresenter.didPresentOnboardingBeforeHandlingActions == true)
                    continuation.resume()
                },
                onAppReadyForInteractions: { }
            )
        }
    }

}
