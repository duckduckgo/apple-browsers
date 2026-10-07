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
import Core
import PixelKit
import PrivacyConfig
import FeatureFlags_iOS

@MainActor
protocol KeyboardPresenting {

    func showKeyboardOnLaunch(lastBackgroundDate: Date?, hasCompletedAuthentication: Bool, isAfterIdleReturn: Bool)

}

@MainActor
protocol AppOpenKeyboardHandling: AnyObject {
    var isNewTabPageVisible: Bool { get }
    var appOpenKeyboardRequestID: UUID { get }
    func runWhenAppOpenKeyboardWindowVisible(_ handler: @escaping () -> Void)
    func closeScreensOverNewTabPageForIdleReturn(completion: @escaping () -> Void)
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
    private let pixelFiring: (any PixelKitFiring)?
    private let onAppLaunch: () -> Bool
    private let schedule: (@escaping () -> Void) -> Void

    init(mainViewController: any AppOpenKeyboardHandling,
         featureFlagger: FeatureFlagger,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared,
         onAppLaunch: @escaping () -> Bool = { KeyboardSettings().onAppLaunch },
         schedule: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: $0) }) {
        self.mainViewController = mainViewController
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.onAppLaunch = onAppLaunch
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
        let scheduleKeyboard = { [self] in
            guard isAppOpen else { return }
            if flagOn, !isCurrentRequest(requestID) { return }
            schedule { [self] in
                if flagOn {
                    guard isCurrentRequest(requestID) else { return }
                    let didShowKeyboard = mainViewController.showKeyboardOnAppOpenIfAllowed()
                    if didShowKeyboard && onAppLaunch && !mainViewController.isNewTabPageVisible {
                        pixelFiring?.fire(Pixel.Event.keyboardOnAppLaunchUsedDaily, frequency: .dailyAndCount)
                    }
                } else {
                    mainViewController.enterSearchOnAppOpen()
                }
            }
        }

        guard flagOn else {
            scheduleKeyboard()
            return
        }
        mainViewController.runWhenAppOpenKeyboardWindowVisible { [self] in
            guard isCurrentRequest(requestID) else { return }
            if isAfterIdleReturn && mainViewController.isNewTabPageVisible {
                mainViewController.closeScreensOverNewTabPageForIdleReturn(completion: scheduleKeyboard)
            } else {
                scheduleKeyboard()
            }
        }
    }

    private func isCurrentRequest(_ requestID: UUID) -> Bool {
        mainViewController.appOpenKeyboardRequestID == requestID && featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage)
    }

}

extension MainViewController: AppOpenKeyboardHandling { }
