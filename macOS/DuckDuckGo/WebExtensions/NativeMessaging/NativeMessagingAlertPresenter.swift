//
//  NativeMessagingAlertPresenter.swift
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

import AppKit
import PixelKit
import WebExtensions
import WebKit

/// Tells the user that an extension can't talk to apps on their Mac in the App Store build, once the extension
/// has tried, until they ask not to be told again for that extension.
@available(macOS 15.4, *)
@MainActor
protocol NativeMessagingAlertPresenterProtocol {
    func explain(_ context: WKWebExtensionContext) async
    /// Only for extensions that require native messaging, such as 1Password. Those that request it at runtime,
    /// such as Bitwarden, still work without it, so they're told when they ask.
    func explainOnActionClick(_ context: WKWebExtensionContext) async
}

@available(macOS 15.4, *)
@MainActor
final class NativeMessagingAlertPresenter: NativeMessagingAlertPresenterProtocol {
    private let limitationProvider: () -> NativeMessagingLimitationProviding?
    private let alertPresenter: WebExtensionAlertPresenterProtocol
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: (any PixelKitFiring)?

    init(
        limitationProvider: @escaping () -> NativeMessagingLimitationProviding?,
        alertPresenter: WebExtensionAlertPresenterProtocol,
        windowControllersManager: WindowControllersManagerProtocol,
        pixelFiring: (any PixelKitFiring)? = PixelKit.shared
    ) {
        self.limitationProvider = limitationProvider
        self.alertPresenter = alertPresenter
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
    }

    func explain(_ context: WKWebExtensionContext) async {
        await explain(context, source: .permissionRequest)
    }

    func explainOnActionClick(_ context: WKWebExtensionContext) async {
        guard context.webExtension.requestedPermissions.contains(.nativeMessaging) else { return }
        await explain(context, source: .toolbarClick)
    }

    private func explain(_ context: WKWebExtensionContext, source: NativeMessagingAlertSource) async {
        let identifier = context.uniqueIdentifier
        guard let limitationProvider = limitationProvider(),
              limitationProvider.hasHitNativeMessagingLimitation(identifier: identifier),
              !limitationProvider.isNativeMessagingAlertSuppressed(identifier: identifier) else { return }

        let pixelExtension = limitationProvider.pixelExtension(identifier: identifier)
        pixelFiring?.fire(WebExtensionPixel.nativeMessagingAlertShown(extension: pixelExtension, source: source), frequency: .dailyAndCount)
        let response = await alertPresenter.present(.nativeMessagingUnavailable(for: context.webExtension))
        switch response {
        case .confirmed(isChecked: true), .secondary(isChecked: true):
            limitationProvider.suppressNativeMessagingAlert(identifier: identifier)
        case .confirmed(isChecked: false), .secondary(isChecked: false), .cancelled:
            break
        }
        if case .secondary = response {
            pixelFiring?.fire(WebExtensionPixel.nativeMessagingAlertLearnMoreClicked(extension: pixelExtension), frequency: .dailyAndCount)
            windowControllersManager.show(url: .ddgLearnMore, tabId: nil, source: .ui, newTab: true, selected: true)
        }
    }
}
