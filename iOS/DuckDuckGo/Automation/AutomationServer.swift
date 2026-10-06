//
//  AutomationServer.swift
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

import AutomationServer
import Core
import Foundation
import WebKit
import os.log

/// iOS-specific implementation of BrowserAutomationProvider
@MainActor
final class IOSAutomationProvider: BrowserAutomationProvider {
    let main: MainViewController

    init(main: MainViewController) {
        self.main = main
    }

    var currentTabHandle: String? {
        main.currentTab?.tabModel.uid
    }

    var isLoading: Bool {
        main.currentTab?.isLoading ?? false
    }

    var isContentBlockerReady: Bool {
        // Content blocker is ready when rules have been compiled
        !ContentBlocking.shared.contentBlockingManager.currentRules.isEmpty
    }

    var currentURL: URL? {
        main.currentTab?.webView.url
    }

    var currentWebView: WKWebView? {
        main.currentTab?.webView
    }

    func navigate(to url: URL) -> Bool {
        guard main.currentTab != nil else {
            return false
        }
        main.loadUrl(url)
        return true
    }

    func getAllTabHandles() -> [String] {
        main.tabManager.currentTabsModel.tabs.compactMap { tab in
            main.tabManager.controller(for: tab)?.tabModel.uid
        }
    }

    func closeCurrentTab() {
        guard let currentTab = main.currentTab else { return }
        main.closeTab(currentTab.tabModel)
    }

    func switchToTab(handle: String) -> Bool {
        if let tab = main.tabManager.currentTabsModel.tabs.first(where: { tab in
            guard let tabView = main.tabManager.controller(for: tab) else {
                return false
            }
            return tabView.tabModel.uid == handle
        }) {
            _ = main.tabManager.select(tab)
            return true
        }
        return false
    }

    func newTab() -> String? {
        main.newTab()
        return main.tabManager.current(createIfNeeded: true)?.tabModel.uid
    }

    func executeScript(_ script: String, args: [String: Any]) async -> Result<Any?, Error> {
        guard let result = await main.executeScript(script, args: args) else {
            return .failure(AutomationServerError.scriptExecutionFailed)
        }
        return result.mapError { $0 as Error }
    }

    func takeScreenshot(rect: CGRect?) async -> Data? {
        guard let webView = currentWebView else { return nil }

        return await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            if let rect = rect {
                config.rect = rect
            }
            webView.takeSnapshot(with: config) { image, _ in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image.pngData())
            }
        }
    }
}

/// Wrapper that creates the automation server with the iOS provider
@MainActor
final class AutomationServer {
    private let core: AutomationServerCore?

    init(main: MainViewController, port: Int?) {
        let provider = IOSAutomationProvider(main: main)
        do {
            self.core = try AutomationServerCore(provider: provider, port: port)
        } catch {
            Logger.automationServer.error("Failed to start automation server: \(error)")
            self.core = nil
        }
    }
}
