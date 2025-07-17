//
//  DBPDebugWebViewWindowManager.swift
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
import DataBrokerProtectionCore
import DataBrokerProtection_iOS

class DBPDebugWebViewWindowManager {
    private weak var webViewHandler: WebViewHandler?

    var isWebViewAvailable: Bool {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                if let navController = window.rootViewController as? UINavigationController,
                   let title = navController.topViewController?.title,
                   title.hasPrefix("PIR Debug Mode") {
                    return true
                }
            }
        }

        return false
    }

    var isWebViewVisible: Bool {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                if let navController = window.rootViewController as? UINavigationController,
                   let title = navController.topViewController?.title,
                   title.hasPrefix("PIR Debug Mode") {
                    return window.isKeyWindow
                }
            }
        }

        return false
    }

    init(webViewHandler: WebViewHandler) {
        self.webViewHandler = webViewHandler
    }

    func showWebView(title: String = "PIR Debug Mode") {
        guard !isWebViewVisible else { return }

        // Find the PIR Debug Mode window and make it visible with a Close button
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                for window in windowScene.windows {
                    if let navController = window.rootViewController as? UINavigationController,
                       let topViewController = navController.topViewController,
                       let currentTitle = topViewController.title,
                       currentTitle.hasPrefix("PIR Debug Mode") {
                        let closeButton = UIBarButtonItem(
                            title: "Close",
                            style: .done,
                            target: self,
                            action: #selector(self.closeWebView)
                        )

                        topViewController.navigationItem.rightBarButtonItem = closeButton
                        topViewController.title = title

                        window.makeKeyAndVisible()
                        break
                    }
                }
            }
        }
    }

    @objc private func closeWebView() {
        hideWebView()
    }

    func hideWebView() {
        guard isWebViewVisible else { return }

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                for window in windowScene.windows {
                    if let navController = window.rootViewController as? UINavigationController,
                       let title = navController.topViewController?.title,
                       title.hasPrefix("PIR Debug Mode") {
                        window.isHidden = true
                        break
                    }
                }
            }
        }
    }
}
