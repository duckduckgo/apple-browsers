//
//  KeyboardPresenter.swift
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
import Core
import PixelKit
import PrivacyConfig
import FeatureFlags_iOS

@MainActor
protocol KeyboardPresenting {

    func showKeyboardOnLaunch(lastBackgroundDate: Date?, hasCompletedAuthentication: Bool, isAfterIdleReturn: Bool)
    func showKeyboardOnNewTabPageCreated()

}

@MainActor
protocol AppOpenKeyboardHandling: AnyObject {
    var isNewTabPageVisible: Bool { get }
    var appOpenKeyboardRequestID: UUID { get }
    func runWhenAppOpenKeyboardWindowVisible(_ handler: @escaping () -> Void)
    var presentedViewController: UIViewController? { get }
    func closeScreensOverNewTabPageForIdleReturn(screenLeftOpen: UIViewController?, completion: @escaping () -> Void)
    func showKeyboardOnAppOpenIfAllowed() -> Bool
    func enterSearchOnAppOpen()
}

/// Keyboard rule for NTP landings behind `.alwaysShowKeyboardOnNewTabPage`: an NTP shows the keyboard
/// when New Tab is on, unless the user dismissed it or onboarding is running.
/// Callers check the flag and onboarding; flag-off paths keep their own conditions.
struct NewTabPageKeyboardPolicy {

    static let appOpenBackgroundThreshold = TimeInterval(20)

    let onNewTab: Bool
    let onAppLaunch: Bool

    /// `nil` means a cold start. Until App Lock is first unlocked, a return still counts as that cold start,
    /// so backgrounding the lock screen briefly doesn't use it up.
    static func isAppOpen(lastBackgroundDate: Date?, hasCompletedAuthentication: Bool = true, now: Date = Date()) -> Bool {
        guard hasCompletedAuthentication, let lastBackgroundDate else { return true }
        return now.timeIntervalSince(lastBackgroundDate) > appOpenBackgroundThreshold
    }

    /// New Tab alone decides on an NTP; App Launch keeps its meaning for other tabs.
    func showsKeyboardOnAppOpen(onNewTabPage: Bool) -> Bool {
        onNewTabPage ? onNewTab : onAppLaunch
    }

}

extension NewTabPageKeyboardPolicy {

    init(settings: KeyboardSettings = KeyboardSettings()) {
        self.init(onNewTab: settings.onNewTab, onAppLaunch: settings.onAppLaunch)
    }

}

final class KeyboardPresenter: KeyboardPresenting {

    private let mainViewController: any AppOpenKeyboardHandling
    private let featureFlagger: FeatureFlagger
    private let runOnceModalPromptCloses: (@escaping @MainActor () -> Bool, @escaping @MainActor () -> Void) -> Bool
    private let pixelFiring: (any PixelKitFiring)?
    private let onAppLaunch: () -> Bool
    private let scheduleAfterPrompt: (@escaping () -> Void) -> Void
    private let schedule: (@escaping () -> Void) -> Void
    private var hasForegroundEnded = false

    init(mainViewController: any AppOpenKeyboardHandling,
         featureFlagger: FeatureFlagger,
         runOnceModalPromptCloses: @escaping (@escaping @MainActor () -> Bool, @escaping @MainActor () -> Void) -> Bool = { _, _ in false },
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         onAppLaunch: @escaping () -> Bool = { KeyboardSettings().onAppLaunch },
         scheduleAfterPrompt: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: $0) },
         schedule: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: $0) }) {
        self.mainViewController = mainViewController
        self.featureFlagger = featureFlagger
        self.runOnceModalPromptCloses = runOnceModalPromptCloses
        self.pixelFiring = pixelFiring
        self.onAppLaunch = onAppLaunch
        self.scheduleAfterPrompt = scheduleAfterPrompt
        self.schedule = schedule
    }

    func showKeyboardOnLaunch(lastBackgroundDate: Date? = nil, hasCompletedAuthentication: Bool = true, isAfterIdleReturn: Bool = false) {
        let flagOn = featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage)
        let onAppLaunch = onAppLaunch()
        guard flagOn || onAppLaunch else { return }
        let isAppOpen = NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate,
                                                           hasCompletedAuthentication: !flagOn || hasCompletedAuthentication)
        if !flagOn && isAppOpen && onAppLaunch {
            pixelFiring?.fire(Pixel.Event.keyboardOnAppLaunchUsedDaily, frequency: .dailyAndCount)
        }

        let requestID = mainViewController.appOpenKeyboardRequestID
        // Captured before any App Lock wait, which a launch prompt can be presented during.
        let screenLeftOpen = mainViewController.presentedViewController
        let scheduleKeyboard = { [self] in
            guard isAppOpen else { return }
            scheduleKeyboardFocus(requestID: requestID, flagOn: flagOn, onAppLaunch: onAppLaunch)
        }

        guard flagOn else {
            scheduleKeyboard()
            return
        }
        scheduleKeyboardWhenWindowVisible(requestID: requestID,
                                          isAfterIdleReturn: isAfterIdleReturn,
                                          screenLeftOpen: screenLeftOpen,
                                          scheduleKeyboard: scheduleKeyboard)
    }

    private func scheduleKeyboardWhenWindowVisible(requestID: UUID,
                                                   isAfterIdleReturn: Bool,
                                                   screenLeftOpen: UIViewController?,
                                                   scheduleKeyboard: @escaping () -> Void) {
        // A launch task can finish after its foreground ended; replacing the next foreground's wait would drop its keyboard.
        guard isCurrentRequest(requestID) else { return }
        mainViewController.runWhenAppOpenKeyboardWindowVisible { [self] in
            guard isCurrentRequest(requestID) else { return }
            if isAfterIdleReturn && mainViewController.isNewTabPageVisible {
                mainViewController.closeScreensOverNewTabPageForIdleReturn(screenLeftOpen: screenLeftOpen, completion: scheduleKeyboard)
            } else {
                scheduleKeyboard()
            }
        }
    }

    /// Each foreground has its own presenter, so a launch task that outlives it can't raise the keyboard on a later one.
    func foregroundDidEnd() {
        hasForegroundEnded = true
    }

    /// A page created for an idle return follows New Tab behavior, without the app-open time threshold.
    func showKeyboardOnNewTabPageCreated() {
        guard featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage) else { return }
        scheduleKeyboardFocus(requestID: mainViewController.appOpenKeyboardRequestID, flagOn: true, onAppLaunch: false)
    }

    private func scheduleKeyboardFocus(requestID: UUID, flagOn: Bool, onAppLaunch: Bool) {
        if flagOn, !isCurrentRequest(requestID) { return }
        schedule { [self] in
            if flagOn {
                guard isCurrentRequest(requestID) else { return }
                let waitsForLaunchPrompt = runOnceModalPromptCloses({ [weak self] in
                    self?.isCurrentRequest(requestID) == true
                }, { [weak self] in
                    self?.showKeyboardAfterLaunchPrompt(requestID: requestID, onAppLaunch: onAppLaunch)
                })
                guard !waitsForLaunchPrompt else { return }
                showKeyboardOnAppOpen(onAppLaunch: onAppLaunch)
            } else {
                mainViewController.enterSearchOnAppOpen()
            }
        }
    }

    private func showKeyboardAfterLaunchPrompt(requestID: UUID, onAppLaunch: Bool) {
        guard isCurrentRequest(requestID) else { return }
        // Let a prompt's destination finish opening before deciding whether to focus.
        scheduleAfterPrompt { [self] in
            guard isCurrentRequest(requestID) else { return }
            showKeyboardOnAppOpen(onAppLaunch: onAppLaunch)
        }
    }

    private func showKeyboardOnAppOpen(onAppLaunch: Bool) {
        let didShowKeyboard = mainViewController.showKeyboardOnAppOpenIfAllowed()
        if didShowKeyboard && onAppLaunch && !mainViewController.isNewTabPageVisible {
            pixelFiring?.fire(Pixel.Event.keyboardOnAppLaunchUsedDaily, frequency: .dailyAndCount)
        }
    }

    private func isCurrentRequest(_ requestID: UUID) -> Bool {
        !hasForegroundEnded
            && mainViewController.appOpenKeyboardRequestID == requestID
            && featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage)
    }

}

extension MainViewController: AppOpenKeyboardHandling { }
