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
    /// Completes after any screen dismissal and New Tab Page creation finish.
    func showNewTabPageAfterIdleReturn(timeAwayMs: Int?, isFirstForeground: Bool, completion: @escaping (IdleReturnNewTabPageResult) -> Void)
    /// Completes like `showNewTabPageAfterIdleReturn`, for the New Tab Page the launch already drew.
    func recordNewTabPageDrawnAtLaunch(timeAwayMs: Int?, completion: @escaping (IdleReturnNewTabPageResult) -> Void)
    func markLastUsedTabAsResumedAfterIdle(timeAwayMs: Int?)
    /// A standard-launch return that did not qualify for an after-idle treatment.
    func recordOrdinaryReturn(timeAwayMs: Int?)
}

enum IdleReturnNewTabPageResult {
    case keptCurrent
    case openedNewTab
    case suppressed
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
    /// Decided when the app comes to the foreground, so a background during the auth wait can't change it.
    private let idleReturnOutcome: IdleReturnOutcome
    private let idleReturnLaunchLanding: IdleReturnLaunchLanding
    private let featureFlagger: FeatureFlagger
    private weak var idleReturnDelegate: IdleReturnLaunchDelegate?

    init(urlHandler: URLHandling,
         shortcutItemHandler: ShortcutItemHandling,
         userActivityHandler: UserActivityHandling,
         keyboardPresenter: KeyboardPresenting,
         launchSourceService: LaunchSourceManaging,
         idleReturnOutcome: IdleReturnOutcome,
         idleReturnLaunchLanding: IdleReturnLaunchLanding,
         featureFlagger: FeatureFlagger,
         idleReturnDelegate: IdleReturnLaunchDelegate? = nil,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.urlHandler = urlHandler
        self.shortcutItemHandler = shortcutItemHandler
        self.userActivityHandler = userActivityHandler
        self.keyboardPresenter = keyboardPresenter
        self.launchSourceManager = launchSourceService
        self.idleReturnOutcome = idleReturnOutcome
        self.idleReturnLaunchLanding = idleReturnLaunchLanding
        self.featureFlagger = featureFlagger
        self.idleReturnDelegate = idleReturnDelegate
        self.pixelFiring = pixelFiring
    }

    func handleLaunchAction(_ action: LaunchAction) {
        // Taken by whichever action comes first, so a link can't leave it behind for a later return.
        let drewNewTabPage = idleReturnLaunchLanding.takeDrawnNewTabPage()
        switch action {
        case .openURL(let url):
            launchSourceManager.setSource(.URL)
            openURL(url)
            recordNewTabPageLeftUnderAction(drewNewTabPage)
        case .handleShortcutItem(let shortcutItem):
            launchSourceManager.setSource(.shortcut)
            shortcutItemHandler.handleShortcutItem(shortcutItem)
            recordNewTabPageLeftUnderAction(drewNewTabPage)
        case .handleUserActivity(let userActivity):
            launchSourceManager.setSource(.standard)
            userActivityHandler.handleUserActivity(userActivity)
            recordNewTabPageLeftUnderAction(drewNewTabPage)
        case .standardLaunch(let lastBackgroundDate, let isFirstForeground, let hasCompletedAuthentication):
            launchSourceManager.setSource(.standard)
            // A New Tab Page the launch drew stands; the rest is the outcome decided on foreground.
            let outcome: IdleReturnOutcome = drewNewTabPage ? .afterIdle(treatment: .ntp, timeAwayMs: idleReturnOutcome.timeAwayMs) : idleReturnOutcome
            let isAfterIdleReturn = outcome.isAfterIdle
            switch outcome {
            case .afterIdle(.ntp, let timeAwayMs):
                let flagOn = featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage)
                let showKeyboard: (IdleReturnNewTabPageResult) -> Void = { [self] result in
                    guard flagOn, featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage) else { return }
                    switch result {
                    case .keptCurrent:
                        // Preparation already closed the old screen; don't dismiss a newly presented launch prompt.
                        keyboardPresenter.showKeyboardOnLaunch(lastBackgroundDate: isFirstForeground ? nil : lastBackgroundDate,
                                                               hasCompletedAuthentication: hasCompletedAuthentication,
                                                               isAfterIdleReturn: false)
                    case .openedNewTab:
                        keyboardPresenter.showKeyboardOnNewTabPageCreated()
                    case .suppressed:
                        break
                    }
                }
                if drewNewTabPage {
                    idleReturnDelegate?.recordNewTabPageDrawnAtLaunch(timeAwayMs: timeAwayMs, completion: showKeyboard)
                } else {
                    idleReturnDelegate?.showNewTabPageAfterIdleReturn(timeAwayMs: timeAwayMs, isFirstForeground: isFirstForeground, completion: showKeyboard)
                }
                return
            case .afterIdle(.lut, let timeAwayMs):
                idleReturnDelegate?.markLastUsedTabAsResumedAfterIdle(timeAwayMs: timeAwayMs)
            case .ordinary(let timeAwayMs):
                idleReturnDelegate?.recordOrdinaryReturn(timeAwayMs: timeAwayMs)
            }
            keyboardPresenter.showKeyboardOnLaunch(lastBackgroundDate: isFirstForeground ? nil : lastBackgroundDate,
                                                   hasCompletedAuthentication: hasCompletedAuthentication,
                                                   isAfterIdleReturn: isAfterIdleReturn)
        }
    }
    
    /// A page a background launch drew stays under an action that only presents a screen, so its arrival
    /// is recorded once seen rather than left for a later return. A page the action replaces records nothing.
    private func recordNewTabPageLeftUnderAction(_ drewNewTabPage: Bool) {
        guard drewNewTabPage else { return }
        idleReturnDelegate?.recordNewTabPageDrawnAtLaunch(timeAwayMs: idleReturnOutcome.timeAwayMs) { _ in }
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
