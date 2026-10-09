//
//  KeyboardPresenterTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Core
import FeatureFlags_iOS
@testable import DuckDuckGo
@_spi(Testing) import PixelKit

@MainActor
private final class MockAppOpenKeyboardHandler: AppOpenKeyboardHandling {
    var isNewTabPageVisible = true
    var appOpenKeyboardRequestID = UUID()
    var dismissalCompletion: (() -> Void)?
    var closeScreensCallCount = 0
    var allowedKeyboardCallCount = 0
    var keyboardWasShown = true
    var legacyKeyboardCallCount = 0
    var presentedViewController: UIViewController?
    var closedScreen: UIViewController?
    var isWindowVisible = true
    var windowVisibleHandler: (() -> Void)?

    func runWhenAppOpenKeyboardWindowVisible(_ handler: @escaping () -> Void) {
        if isWindowVisible {
            handler()
        } else {
            windowVisibleHandler = handler
        }
    }
    var completesFocusImmediately = true
    var focusCompletion: ((Bool) -> Void)?

    func closeScreensOverNewTabPageForIdleReturn(screenLeftOpen: UIViewController?, completion: @escaping () -> Void) {
        closeScreensCallCount += 1
        closedScreen = screenLeftOpen
        dismissalCompletion = completion
    }

    func showKeyboardOnAppOpenIfAllowed(completion: @escaping (Bool) -> Void) {
        allowedKeyboardCallCount += 1
        if completesFocusImmediately {
            completion(keyboardWasShown)
        } else {
            focusCompletion = completion
        }
    }

    func enterSearchOnAppOpen() {
        legacyKeyboardCallCount += 1
    }
}

@MainActor
final class KeyboardPresenterTests {
    private let target = MockAppOpenKeyboardHandler()
    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
    private let pixelFiring = PixelKitMock()
    private var onAppLaunch = false
    private var scheduledActions: [() -> Void] = []
    private var afterPromptActions: [() -> Void] = []
    private var promptPending = false
    private var promptRequestIsValid: (@MainActor () -> Bool)?
    private var promptCloseHandler: (@MainActor () -> Void)?
    private lazy var presenter = KeyboardPresenter(
        mainViewController: target,
        featureFlagger: featureFlagger,
        runOnceModalPromptCloses: { [unowned self] isValid, handler in
            guard promptPending else { return false }
            promptRequestIsValid = isValid
            promptCloseHandler = handler
            return true
        },
        pixelFiring: pixelFiring,
        onAppLaunch: { [unowned self] in onAppLaunch },
        scheduleAfterPrompt: { [unowned self] in afterPromptActions.append($0) },
        schedule: { [unowned self] in scheduledActions.append($0) })

    @available(iOS 16, macOS 13, *)
    @Test("Cold launch preserves each flag path and the App Launch pixel condition", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func coldLaunch(flagOn: Bool, launchSetting: Bool) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = launchSetting
        target.isNewTabPageVisible = false

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: false)

        #expect(target.closeScreensCallCount == 0)
        #expect(scheduledActions.count == (flagOn || launchSetting ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.count == (!flagOn && launchSetting ? 1 : 0))
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 0)

        scheduledActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == (flagOn ? 1 : 0))
        #expect(target.legacyKeyboardCallCount == (!flagOn && launchSetting ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.count == (launchSetting ? 1 : 0))
        if launchSetting {
            #expect(pixelFiring.actualFireCalls.first?.pixel.name == Pixel.Event.keyboardOnAppLaunchUsedDaily.name)
            #expect(pixelFiring.actualFireCalls.first?.frequency == .dailyAndCount)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Both flag paths keep the 20-second background threshold", .timeLimit(.minutes(1)), arguments: [false, true], [5.0, 25.0])
    func backgroundThreshold(flagOn: Bool, secondsInBackground: TimeInterval) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = true
        target.isNewTabPageVisible = false

        presenter.showKeyboardOnLaunch(lastBackgroundDate: Date().addingTimeInterval(-secondsInBackground), isAfterIdleReturn: true)

        #expect(target.closeScreensCallCount == 0)
        #expect(scheduledActions.count == (secondsInBackground == 25 ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.count == (!flagOn && secondsInBackground == 25 ? 1 : 0))
        scheduledActions.forEach { $0() }
        #expect(pixelFiring.actualFireCalls.count == (secondsInBackground == 25 ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("App Launch usage requires successful focus on another tab", .timeLimit(.minutes(1)), arguments: [
        (false, false),
        (true, true)
    ])
    func appLaunchPixelRequiresFocusOnAnotherTab(onNewTabPage: Bool, keyboardWasShown: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        onAppLaunch = true
        target.isNewTabPageVisible = onNewTabPage
        target.keyboardWasShown = keyboardWasShown

        presenter.showKeyboardOnLaunch()

        #expect(pixelFiring.actualFireCalls.isEmpty)
        scheduledActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == 1)
        #expect(pixelFiring.actualFireCalls.count == (!onNewTabPage && keyboardWasShown ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("App Launch usage waits for the actual asynchronous focus result", .timeLimit(.minutes(1)), arguments: [false, true])
    func appLaunchPixelWaitsForFocusCompletion(keyboardWasShown: Bool) throws {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        onAppLaunch = true
        target.isNewTabPageVisible = false
        target.completesFocusImmediately = false

        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == 1)
        #expect(pixelFiring.actualFireCalls.isEmpty)
        let completion = try #require(target.focusCompletion)
        completion(keyboardWasShown)

        #expect(pixelFiring.actualFireCalls.count == (keyboardWasShown ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cancelled request or disabled flag cannot record delayed App Launch usage", .timeLimit(.minutes(1)), arguments: [false, true])
    func invalidatedFocusCompletionDoesNotRecordUsage(disableFlag: Bool) throws {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        onAppLaunch = true
        target.isNewTabPageVisible = false
        target.completesFocusImmediately = false
        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }
        let completion = try #require(target.focusCompletion)

        if disableFlag {
            featureFlagger.enabledFeatureFlags = []
        } else {
            target.appOpenKeyboardRequestID = UUID()
        }
        completion(true)

        #expect(pixelFiring.actualFireCalls.isEmpty)
        #expect(target.legacyKeyboardCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An idle return waits for dismissal but never bypasses the keyboard threshold", .timeLimit(.minutes(1)), arguments: [false, true])
    func idleReturnWaitsForDismissal(isAppOpen: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        let lastBackgroundDate = isAppOpen ? nil : Date().addingTimeInterval(-1)

        presenter.showKeyboardOnLaunch(lastBackgroundDate: lastBackgroundDate, isAfterIdleReturn: true)

        #expect(target.closeScreensCallCount == 1)
        #expect(scheduledActions.isEmpty)
        #expect(target.allowedKeyboardCallCount == 0)

        target.dismissalCompletion?()

        #expect(scheduledActions.count == (isAppOpen ? 1 : 0))
        scheduledActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == (isAppOpen ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cancelled request or disabled flag cannot focus after dismissal or delay", .timeLimit(.minutes(1)), arguments: [
        (true, false),
        (false, false),
        (false, true)
    ])
    func invalidatedRequest(beforeDismissal: Bool, disableFlag: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        onAppLaunch = true
        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)
        if !beforeDismissal {
            target.dismissalCompletion?()
            #expect(scheduledActions.count == 1)
        }

        if disableFlag {
            featureFlagger.enabledFeatureFlags = []
        } else {
            target.appOpenKeyboardRequestID = UUID()
        }
        if beforeDismissal {
            target.dismissalCompletion?()
            #expect(scheduledActions.isEmpty)
        }
        scheduledActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 0)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off requests retain their policy across flag changes but respect cancellation", .timeLimit(.minutes(1)), arguments: [false, true])
    func flagOffPreservesLegacyCallback(cancelRequest: Bool) {
        featureFlagger.enabledFeatureFlags = []
        onAppLaunch = true
        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)
        if cancelRequest {
            target.appOpenKeyboardRequestID = UUID()
        }
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]

        scheduledActions.forEach { $0() }

        #expect(target.closeScreensCallCount == 0)
        #expect(target.legacyKeyboardCallCount == (cancelRequest ? 0 : 1))
        #expect(target.allowedKeyboardCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A pending prompt defers keyboard focus and usage recording", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func promptDefersKeyboard(onNewTabPage: Bool, keyboardWasShown: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        promptPending = true
        onAppLaunch = true
        target.isNewTabPageVisible = onNewTabPage
        target.keyboardWasShown = keyboardWasShown
        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }
        #expect(pixelFiring.actualFireCalls.isEmpty)
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(promptRequestIsValid?() == true)

        promptCloseHandler?()
        #expect(afterPromptActions.count == 1)
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(pixelFiring.actualFireCalls.isEmpty)
        afterPromptActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == 1)
        #expect(pixelFiring.actualFireCalls.count == (!onNewTabPage && keyboardWasShown ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Invalidating a request stops waiting and focus after a prompt", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func invalidatedPromptRequest(afterClose: Bool, disableFlag: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        promptPending = true
        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }
        if afterClose {
            promptCloseHandler?()
            #expect(afterPromptActions.count == 1)
        }

        if disableFlag {
            featureFlagger.enabledFeatureFlags = []
        } else {
            target.appOpenKeyboardRequestID = UUID()
        }
        #expect(promptRequestIsValid?() == false)
        if !afterClose {
            promptCloseHandler?()
            #expect(afterPromptActions.isEmpty)
        }
        afterPromptActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off launch never subscribes to prompt closure", .timeLimit(.minutes(1)))
    func flagOffDoesNotWaitForPrompt() {
        featureFlagger.enabledFeatureFlags = []
        promptPending = true
        onAppLaunch = true
        presenter.showKeyboardOnLaunch()
        scheduledActions.forEach { $0() }
        #expect(promptCloseHandler == nil)
        #expect(target.legacyKeyboardCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A newly created page waits for a prompt without using the App Launch setting", .timeLimit(.minutes(1)),
          arguments: [false, true], [false, true])
    func createdNewTabPageWaitsForPrompt(flagOn: Bool, launchSetting: Bool) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = launchSetting
        promptPending = true

        presenter.showKeyboardOnNewTabPageCreated()

        #expect(target.closeScreensCallCount == 0)
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(scheduledActions.count == (flagOn ? 1 : 0))
        scheduledActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(promptRequestIsValid?() == (flagOn ? true : nil))

        promptCloseHandler?()
        afterPromptActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == (flagOn ? 1 : 0))
        #expect(target.legacyKeyboardCallCount == 0)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page created behind App Lock holds its keyboard until unlock", .timeLimit(.minutes(1)))
    func createdNewTabPageWaitsForUnlock() {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        target.isWindowVisible = false

        presenter.showKeyboardOnNewTabPageCreated()
        scheduledActions.forEach { $0() }

        #expect(scheduledActions.isEmpty)
        #expect(target.allowedKeyboardCallCount == 0)

        target.isWindowVisible = true
        target.windowVisibleHandler?()
        scheduledActions.forEach { $0() }

        #expect(target.closeScreensCallCount == 0)
        #expect(target.allowedKeyboardCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A locked idle return closes the old screen before waiting for unlock and respects cancellation",
          .timeLimit(.minutes(1)), arguments: [false, true])
    func lockedAppWaitsForUnlock(cancelBeforeUnlock: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        target.isWindowVisible = false

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)

        #expect(target.closeScreensCallCount == 1)
        #expect(target.windowVisibleHandler == nil)
        #expect(scheduledActions.isEmpty)
        target.dismissalCompletion?()
        #expect(target.windowVisibleHandler != nil)
        #expect(scheduledActions.isEmpty)

        if cancelBeforeUnlock {
            target.appOpenKeyboardRequestID = UUID()
        }
        target.isWindowVisible = true
        target.windowVisibleHandler?()
        scheduledActions.forEach { $0() }

        #expect(target.closeScreensCallCount == 1)
        #expect(target.allowedKeyboardCallCount == (cancelBeforeUnlock ? 0 : 1))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off requests wait for unlock and respect cancellation", .timeLimit(.minutes(1)), arguments: [false, true])
    func flagOffWaitsForWindow(cancelBeforeUnlock: Bool) {
        featureFlagger.enabledFeatureFlags = []
        onAppLaunch = true
        target.isWindowVisible = false

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: false)
        scheduledActions.forEach { $0() }

        #expect(target.windowVisibleHandler != nil)
        #expect(scheduledActions.isEmpty)
        #expect(target.legacyKeyboardCallCount == 0)
        #expect(pixelFiring.actualFireCalls.count == 1)

        if cancelBeforeUnlock {
            target.appOpenKeyboardRequestID = UUID()
        }
        target.isWindowVisible = true
        target.windowVisibleHandler?()
        scheduledActions.forEach { $0() }

        #expect(target.legacyKeyboardCallCount == (cancelBeforeUnlock ? 0 : 1))
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(pixelFiring.actualFireCalls.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A short return before the first unlock is an app open only with the flag on", .timeLimit(.minutes(1)), arguments: [false, true])
    func returnBeforeFirstUnlock(flagOn: Bool) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = true

        presenter.showKeyboardOnLaunch(lastBackgroundDate: Date().addingTimeInterval(-5),
                                       hasCompletedAuthentication: false,
                                       isAfterIdleReturn: false)

        #expect(scheduledActions.count == (flagOn ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A locked idle return prepares the old screen before a launch prompt and waits for that prompt", .timeLimit(.minutes(1)))
    func lockedIdleReturnClosesOnlyScreenLeftOpen() {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        let settings = UIViewController()
        target.presentedViewController = settings
        target.isWindowVisible = false

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)
        #expect(target.closeScreensCallCount == 1)
        #expect(target.closedScreen === settings)
        #expect(target.windowVisibleHandler == nil)
        target.dismissalCompletion?()

        target.presentedViewController = UIViewController()
        promptPending = true
        target.isWindowVisible = true
        target.windowVisibleHandler?()
        scheduledActions.forEach { $0() }

        #expect(target.closeScreensCallCount == 1)
        #expect(target.closedScreen === settings)
        #expect(promptCloseHandler != nil)
        #expect(target.allowedKeyboardCallCount == 0)

        target.presentedViewController = nil
        promptPending = false
        promptCloseHandler?()
        afterPromptActions.forEach { $0() }
        #expect(target.allowedKeyboardCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A launch task that outlives its foreground cannot raise the keyboard or replace a later wait",
          .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func endedForegroundCannotFocus(flagOn: Bool, endsBeforeRequest: Bool) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = true
        target.isWindowVisible = false
        if endsBeforeRequest {
            presenter.foregroundDidEnd()
        }

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: false)
        presenter.foregroundDidEnd()
        target.isWindowVisible = true
        target.windowVisibleHandler?()
        scheduledActions.forEach { $0() }

        #expect((target.windowVisibleHandler == nil) == endsBeforeRequest)
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 0)
    }
}
