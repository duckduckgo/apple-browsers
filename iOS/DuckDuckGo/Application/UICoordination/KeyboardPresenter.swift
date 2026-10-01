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

    func showKeyboardOnLaunch(lastBackgroundDate: Date?, isAfterIdleReturn: Bool)

}

@MainActor
protocol AppOpenKeyboardHandling: AnyObject {
    var isNewTabPageVisible: Bool { get }
    var appOpenKeyboardRequestID: UUID { get }
    func closeScreensOverNewTabPageForIdleReturn(completion: @escaping () -> Void)
    func showKeyboardOnAppOpenIfAllowed()
    func enterSearchOnAppOpen()
}

/// Keyboard rule for NTP landings behind `.alwaysShowKeyboardOnNewTabPage`: an NTP shows the keyboard
/// when New Tab is on, unless the user dismissed it or onboarding is running.
/// Callers check the flag and onboarding, which after Fire they pass in; flag-off paths keep their own conditions.
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

    /// After Fire, New Tab decides unless onboarding is still running. A burned Duck.ai chat reopens
    /// as a new chat that owns its input. The Search & Duck.ai address bar no longer plays a part:
    /// its old suppression was for onboarding, which now holds the keyboard back for everyone.
    func showsKeyboardAfterFire(onDuckAITab: Bool, stillOnboarding: Bool) -> Bool {
        onNewTab && !onDuckAITab && !stillOnboarding
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

    func showKeyboardOnLaunch(lastBackgroundDate: Date? = nil, isAfterIdleReturn: Bool = false) {
        let flagOn = featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage)
        let onAppLaunch = onAppLaunch()
        guard flagOn || onAppLaunch else { return }
        let isAppOpen = NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate)
        if isAppOpen && onAppLaunch {
            pixelFiring?.fire(Pixel.Event.keyboardOnAppLaunchUsedDaily, frequency: .dailyAndCount)
        }

        let requestID = mainViewController.appOpenKeyboardRequestID
        let scheduleKeyboard = { [self] in
            guard isAppOpen else { return }
            if flagOn, !isCurrentRequest(requestID) { return }
            schedule { [self] in
                if flagOn {
                    guard isCurrentRequest(requestID) else { return }
                    let waitsForLaunchPrompt = runOnceModalPromptCloses({ [weak self] in
                        self?.isCurrentRequest(requestID) == true
                    }, { [weak self] in
                        self?.showKeyboardAfterLaunchPrompt(requestID: requestID)
                    })
                    guard !waitsForLaunchPrompt else { return }
                    mainViewController.showKeyboardOnAppOpenIfAllowed()
                } else {
                    mainViewController.enterSearchOnAppOpen()
                }
            }
        }

        if flagOn && isAfterIdleReturn && mainViewController.isNewTabPageVisible {
            mainViewController.closeScreensOverNewTabPageForIdleReturn(completion: scheduleKeyboard)
        } else {
            scheduleKeyboard()
        }
    }

    private func showKeyboardAfterLaunchPrompt(requestID: UUID) {
        guard isCurrentRequest(requestID) else { return }
        // Let a prompt's destination finish opening before deciding whether to focus.
        scheduleAfterPrompt { [self] in
            guard isCurrentRequest(requestID) else { return }
            mainViewController.showKeyboardOnAppOpenIfAllowed()
        }
    }

    private func isCurrentRequest(_ requestID: UUID) -> Bool {
        mainViewController.appOpenKeyboardRequestID == requestID && featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage)
    }

}

extension MainViewController: AppOpenKeyboardHandling { }
