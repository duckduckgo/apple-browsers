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

enum LaunchAction {

    case openURL(URL)
    case handleShortcutItem(UIApplicationShortcutItem)
    case showKeyboard(Date?)

    init(actionToHandle: AppAction?, lastBackgroundDate: Date?) {
        switch actionToHandle {
        case .openURL(let url)?:
            self = .openURL(url)
        case .handleShortcutItem(let shortcutItem)?:
            self = .handleShortcutItem(shortcutItem)
        case nil:
            self = .showKeyboard(lastBackgroundDate)
        }
    }

}

@MainActor
protocol LaunchActionHandling {

    func handleLaunchAction(_ action: LaunchAction)

}

@MainActor
final class LaunchActionHandler: LaunchActionHandling {

    private let urlHandler: URLHandling
    private let shortcutItemHandler: ShortcutItemHandling
    private let keyboardPresenter: KeyboardPresenting
    private let pixelFiring: PixelFiring.Type

    init(urlHandler: URLHandling,
         shortcutItemHandler: ShortcutItemHandling,
         keyboardPresenter: KeyboardPresenting,
         pixelFiring: PixelFiring.Type = Pixel.self) {
        self.urlHandler = urlHandler
        self.shortcutItemHandler = shortcutItemHandler
        self.keyboardPresenter = keyboardPresenter
        self.pixelFiring = pixelFiring
    }

    func handleLaunchAction(_ action: LaunchAction) {
        switch action {
        case .openURL(let url):
            openURL(url)
        case .handleShortcutItem(let shortcutItem):
            shortcutItemHandler.handleShortcutItem(shortcutItem)
        case .showKeyboard(let lastBackgroundDate):
            keyboardPresenter.showKeyboardOnLaunch(lastBackgroundDate: lastBackgroundDate)
        }
    }

    private func openURL(_ url: URL) {
        Logger.sync.debug("App launched with url \(url.absoluteString)")
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
            pixelFiring.fire(.appLaunchFromExternalLink, withAdditionalParameters: [:])
        } else if url.scheme == AppDeepLinkSchemes.quickLink.rawValue {
            pixelFiring.fire(.appLaunchFromShareExtension, withAdditionalParameters: [:])
        }
    }

}
