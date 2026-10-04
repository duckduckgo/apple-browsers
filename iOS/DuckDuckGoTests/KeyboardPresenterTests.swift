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
    var legacyKeyboardCallCount = 0

    func closeScreensOverNewTabPageForIdleReturn(completion: @escaping () -> Void) {
        closeScreensCallCount += 1
        dismissalCompletion = completion
    }

    func showKeyboardOnAppOpenIfAllowed() {
        allowedKeyboardCallCount += 1
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
    private lazy var presenter = KeyboardPresenter(
        mainViewController: target,
        featureFlagger: featureFlagger,
        pixelFiring: pixelFiring,
        onAppLaunch: { [unowned self] in onAppLaunch },
        schedule: { [unowned self] in scheduledActions.append($0) })

    @available(iOS 16, macOS 13, *)
    @Test("Cold launch preserves each flag path and the App Launch pixel condition", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func coldLaunch(flagOn: Bool, launchSetting: Bool) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = launchSetting

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: false)

        #expect(target.closeScreensCallCount == 0)
        #expect(scheduledActions.count == (flagOn || launchSetting ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.count == (launchSetting ? 1 : 0))
        if launchSetting {
            #expect(pixelFiring.actualFireCalls.first?.pixel.name == Pixel.Event.keyboardOnAppLaunchUsedDaily.name)
            #expect(pixelFiring.actualFireCalls.first?.frequency == .dailyAndCount)
        }
        #expect(target.allowedKeyboardCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 0)

        scheduledActions.forEach { $0() }

        #expect(target.allowedKeyboardCallCount == (flagOn ? 1 : 0))
        #expect(target.legacyKeyboardCallCount == (!flagOn && launchSetting ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Both flag paths keep the 20-second background threshold", .timeLimit(.minutes(1)), arguments: [false, true], [5.0, 25.0])
    func backgroundThreshold(flagOn: Bool, secondsInBackground: TimeInterval) {
        featureFlagger.enabledFeatureFlags = flagOn ? [.alwaysShowKeyboardOnNewTabPage] : []
        onAppLaunch = true

        presenter.showKeyboardOnLaunch(lastBackgroundDate: Date().addingTimeInterval(-secondsInBackground), isAfterIdleReturn: false)

        #expect(scheduledActions.count == (secondsInBackground == 25 ? 1 : 0))
        #expect(pixelFiring.actualFireCalls.count == (secondsInBackground == 25 ? 1 : 0))
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
    @Test("A cancelled request or disabled flag cannot focus after dismissal or delay", .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func invalidatedRequest(beforeDismissal: Bool, disableFlag: Bool) {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
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
    }

    @available(iOS 16, macOS 13, *)
    @Test("Flag-off requests retain legacy scheduling and ignore the cancellation token", .timeLimit(.minutes(1)))
    func flagOffPreservesLegacyCallback() {
        featureFlagger.enabledFeatureFlags = []
        onAppLaunch = true
        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)
        target.appOpenKeyboardRequestID = UUID()
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]

        scheduledActions.forEach { $0() }

        #expect(target.closeScreensCallCount == 0)
        #expect(target.legacyKeyboardCallCount == 1)
        #expect(target.allowedKeyboardCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Idle-return cleanup only runs for a New Tab Page", .timeLimit(.minutes(1)))
    func otherTabsDoNotDismissScreens() {
        featureFlagger.enabledFeatureFlags = [.alwaysShowKeyboardOnNewTabPage]
        target.isNewTabPageVisible = false

        presenter.showKeyboardOnLaunch(lastBackgroundDate: nil, isAfterIdleReturn: true)

        #expect(target.closeScreensCallCount == 0)
        #expect(scheduledActions.count == 1)
    }
}
