//
//  WebExtensionWindowTabProvider+iOS.swift
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
import WebExtensions
import WebKit

@available(iOS 18.4, *)
@MainActor
final class WebExtensionWindowTabProvider: WebExtensionWindowTabProviding {

    private weak var mainViewController: MainViewController?

    init(mainViewController: MainViewController) {
        self.mainViewController = mainViewController
    }

    // MARK: - WebExtensionWindowTabProviding

    func openWindows(for context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        guard let mainViewController else { return [] }
        return [mainViewController]
    }

    func focusedWindow(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        return mainViewController
    }

    func openNewWindow(
        using configuration: WKWebExtension.WindowConfiguration,
        for context: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionWindow)? {
        return mainViewController
    }

    func openNewTab(
        using configuration: WKWebExtension.TabConfiguration,
        for context: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionTab)? {
        guard let mainViewController else { return nil }

        if let url = configuration.url {
            let controller = mainViewController.tabManager.add(url: url, inBackground: false, inheritedAttribution: nil)
            return controller
        }

        mainViewController.tabManager.addHomeTab()
        return mainViewController.tabManager.current(createIfNeeded: true)
    }

    func presentPopup(
        _ action: WKWebExtension.Action,
        for context: WKWebExtensionContext
    ) async throws {
        guard action.presentsPopup,
              let popupWebView = action.popupWebView,
              let mainViewController else {
            return
        }

        let hostingController = UIViewController()
        hostingController.view = popupWebView
        hostingController.modalPresentationStyle = .popover

        if let popover = hostingController.popoverPresentationController {
            popover.sourceView = mainViewController.view
            popover.sourceRect = CGRect(x: mainViewController.view.bounds.midX,
                                        y: mainViewController.view.bounds.minY + 50,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = .up
        }

        mainViewController.present(hostingController, animated: true)
    }
}
