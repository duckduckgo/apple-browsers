//
//  LaunchActionHandler.swift
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
import Core
import PixelKit
import PrivacyConfig
import FeatureFlags_iOS

enum LaunchAction {

    case openURL(URL)
    case handleShortcutItem(UIApplicationShortcutItem)
    case handleUserActivity(NSUserActivity)
    /// `hasCompletedAuthentication` is `false` while App Lock has not been unlocked since launch.
    case standardLaunch(lastBackgroundDate: Date?, isFirstForeground: Bool, hasCompletedAuthentication: Bool = true)

    init(actionToHandle: AppAction?, lastBackgroundDate: Date?, isFirstForeground: Bool = false, hasCompletedAuthentication: Bool = true) {
        switch actionToHandle {
        case .openURL(let url)?:
            self = .openURL(url)
        case .handleShortcutItem(let shortcutItem)?:
            self = .handleShortcutItem(shortcutItem)
        case .handleUserActivity(let userActivity)?:
            self = .handleUserActivity(userActivity)
        case nil:
            self = .standardLaunch(lastBackgroundDate: lastBackgroundDate,
                                   isFirstForeground: isFirstForeground,
                                   hasCompletedAuthentication: hasCompletedAuthentication)
        }
    }

    var url: URL? {
        switch self {
        case .openURL(let url):
            return url
        case .handleShortcutItem, .handleUserActivity, .standardLaunch:
            return nil
        }
    }

}

@MainActor
protocol OnboardingPresenting: AnyObject {
    func startOnboardingFlowIfNotSeenBefore(url: URL?)
}

@MainActor
protocol IdleReturnLaunchDelegate: AnyObject {
    /// Returns `true` only when the current tab is already a New Tab Page, is kept as it is, and no voice chat is active.
    @discardableResult
    func showNewTabPageAfterIdleReturn(timeAwayMs: Int?) -> Bool
    func markLastUsedTabAsResumedAfterIdle(timeAwayMs: Int?)
    /// A standard-launch return that did not qualify for an after-idle treatment.
    func recordOrdinaryReturn(timeAwayMs: Int?)
}

@MainActor
protocol LaunchActionHandling {

    func handleLaunchAction(_ action: LaunchAction)

}

@MainActor
final class LaunchActionHandler: LaunchActionHandling {

    private let urlHandler: URLHandling
    private let shortcutItemHandler: ShortcutItemHandling
    private let userActivityHandler: UserActivityHandling
    private let keyboardPresenter: KeyboardPresenting
    private let pixelFiring: (any PixelKitFiring)?
    private let launchSourceManager: LaunchSourceManaging
    private let idleReturnEvaluator: IdleReturnEvaluating
    private let featureFlagger: FeatureFlagger
    private weak var idleReturnDelegate: IdleReturnLaunchDelegate?

    init(urlHandler: URLHandling,
         shortcutItemHandler: ShortcutItemHandling,
         userActivityHandler: UserActivityHandling,
         keyboardPresenter: KeyboardPresenting,
         launchSourceService: LaunchSourceManaging,
         idleReturnEvaluator: IdleReturnEvaluating,
         featureFlagger: FeatureFlagger,
         idleReturnDelegate: IdleReturnLaunchDelegate? = nil,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.urlHandler = urlHandler
        self.shortcutItemHandler = shortcutItemHandler
        self.userActivityHandler = userActivityHandler
        self.keyboardPresenter = keyboardPresenter
        self.launchSourceManager = launchSourceService
        self.idleReturnEvaluator = idleReturnEvaluator
        self.featureFlagger = featureFlagger
        self.idleReturnDelegate = idleReturnDelegate
        self.pixelFiring = pixelFiring
    }

    func handleLaunchAction(_ action: LaunchAction) {
        switch action {
        case .openURL(let url):
            launchSourceManager.setSource(.URL)
            openURL(url)
        case .handleShortcutItem(let shortcutItem):
            launchSourceManager.setSource(.shortcut)
            shortcutItemHandler.handleShortcutItem(shortcutItem)
        case .handleUserActivity(let userActivity):
            launchSourceManager.setSource(.standard)
            userActivityHandler.handleUserActivity(userActivity)
        case .standardLaunch(let lastBackgroundDate, let isFirstForeground, let hasCompletedAuthentication):
            launchSourceManager.setSource(.standard)
            let timeAwayMs = lastBackgroundDate.map { Int(Date().timeIntervalSince($0) * 1000) }
            let isAfterIdleReturn = idleReturnEvaluator.didReturnAfterIdle(lastBackgroundDate: lastBackgroundDate)
            if isAfterIdleReturn {
                switch idleReturnEvaluator.treatmentForIdleReturn() {
                case .ntp:
                    let keptCurrentNewTabPage = idleReturnDelegate?.showNewTabPageAfterIdleReturn(timeAwayMs: timeAwayMs) ?? false
                    // A kept New Tab Page is an app open like any other, so it falls through to the keyboard presenter.
                    guard keptCurrentNewTabPage, featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage) else { return }
                case .lut:
                    idleReturnDelegate?.markLastUsedTabAsResumedAfterIdle(timeAwayMs: timeAwayMs)
                }
            } else {
                idleReturnDelegate?.recordOrdinaryReturn(timeAwayMs: timeAwayMs)
            }
            keyboardPresenter.showKeyboardOnLaunch(lastBackgroundDate: isFirstForeground ? nil : lastBackgroundDate,
                                                   hasCompletedAuthentication: hasCompletedAuthentication,
                                                   isAfterIdleReturn: isAfterIdleReturn)
        }
    }
    
    private func openURL(_ url: URL) {
        Logger.sync.debug("App launched with url \(url.shortDescription)")
        fireAppLaunchedWithExternalLinkPixel(url: url)
        guard urlHandler.shouldProcessDeepLink(url) else { return }
        NotificationCenter.default.post(name: AutofillLoginListAuthenticator.Notifications.invalidateContext, object: nil)
        urlHandler.handleURL(url)
    }

    private func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
        Logger.general.debug("Handling shortcut item: \(shortcutItem.type)")
        shortcutItemHandler.handleShortcutItem(shortcutItem)
    }

    private func fireAppLaunchedWithExternalLinkPixel(url: URL) {
        // Websites or searches opened via share extensions have `ddgQuickLink` scheme.
        // If scheme is either `http` or `https` we know the app has been opened by clicking directly an external link.
        if url.scheme == "http" || url.scheme == "https" {
            pixelFiring?.fire(Pixel.Event.appLaunchFromExternalLink)
        } else if url.scheme == AppDeepLinkSchemes.quickLink.rawValue {
            pixelFiring?.fire(Pixel.Event.appLaunchFromShareExtension)
        }
    }

}
