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

    func showKeyboardOnLaunch(lastBackgroundDate: Date?)

}

/// Keyboard rule for NTP landings behind `.alwaysShowKeyboardOnNewTabPage`.
/// Callers check the flag; flag-off paths keep their own conditions.
struct NewTabPageKeyboardPolicy {

    static let appOpenBackgroundThreshold = TimeInterval(20)

    let onNewTab: Bool
    let onAppLaunch: Bool

    /// `nil` means a cold start.
    static func isAppOpen(lastBackgroundDate: Date?, now: Date = Date()) -> Bool {
        guard let lastBackgroundDate else { return true }
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

    private let mainViewController: MainViewController
    private let featureFlagger: FeatureFlagger

    init(mainViewController: MainViewController, featureFlagger: FeatureFlagger) {
        self.mainViewController = mainViewController
        self.featureFlagger = featureFlagger
    }

    func showKeyboardOnLaunch(lastBackgroundDate: Date? = nil) {
        if featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage) {
            showKeyboardOnAppOpen(lastBackgroundDate: lastBackgroundDate)
            return
        }

        guard KeyboardSettings().onAppLaunch && NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate) else { return }

        PixelKit.fire(Pixel.Event.keyboardOnAppLaunchUsedDaily, frequency: .dailyAndCount)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mainViewController.enterSearch()
        }
    }

    private func showKeyboardOnAppOpen(lastBackgroundDate: Date?) {
        guard NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate) else { return }

        if KeyboardSettings().onAppLaunch {
            PixelKit.fire(Pixel.Event.keyboardOnAppLaunchUsedDaily, frequency: .dailyAndCount)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mainViewController.showKeyboardOnAppOpenIfAllowed()
        }
    }

}
